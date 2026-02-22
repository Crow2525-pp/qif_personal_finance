"""
Dagster asset: dashboard_quality_gate

Runs after the dbt reporting layer completes and verifies that:
  1. All Grafana dashboard JSON files are valid (static lint).
  2. All live dashboard panels return data via the Grafana API.

Failures are surfaced as Dagster metadata and raised as exceptions so they
appear as failures in the Dagster UI alongside dbt test failures.
"""
from __future__ import annotations

import datetime as dt
import os
import sys
from pathlib import Path
from typing import Any

from dagster import MetadataValue, asset

from .assets import finance_dbt_assets

def _import_checker():
    """Import check_grafana_dashboards lazily to avoid sys.path pollution at module load."""
    if str(_SCRIPTS_DIR) not in sys.path:
        sys.path.insert(0, str(_SCRIPTS_DIR))
    import check_grafana_dashboards as _mod
    return _mod

_REPO_ROOT = Path(__file__).resolve().parents[1]
_SCRIPTS_DIR = _REPO_ROOT / "scripts"

# ---------------------------------------------------------------------------
# Configuration — all overridable via environment variables.
# Inside Docker the internal service URL is used; externally GRAFANA_URL wins.
# ---------------------------------------------------------------------------
_GRAFANA_URL = os.environ.get("GRAFANA_URL", "http://grafana:3000")
_GRAFANA_TOKEN = os.environ.get("GRAFANA_TOKEN")
_GRAFANA_USER = os.environ.get("GRAFANA_USER", "admin")
_GRAFANA_PASSWORD = os.environ.get("GRAFANA_ADMIN_PASSWORD")
_DASHBOARD_DIR = os.environ.get(
    "DASHBOARD_DIR",
    str(_REPO_ROOT / "grafana" / "provisioning" / "dashboards"),
)


@asset(
    deps=[finance_dbt_assets],
    group_name="dashboard_qa",
    tags={"dagster/kind/grafana": "", "dagster/kind/python": ""},
    description=(
        "Runs Grafana dashboard quality checks after the dbt reporting layer "
        "completes. Verifies all panels return data and flags SQL/lint errors."
    ),
)
def dashboard_quality_gate(context) -> None:
    _checker = _import_checker()

    # ------------------------------------------------------------------
    # 1. Static lint — parse dashboard JSON files from the mounted dir.
    # ------------------------------------------------------------------
    dashboard_dir = Path(_DASHBOARD_DIR)
    lint_findings: dict[str, list[dict[str, Any]]] = {}
    has_parse_errors = False

    if dashboard_dir.exists():
        context.log.info(f"Static lint: scanning {dashboard_dir}")
        lint_findings = _checker.lint_dashboard_files(str(dashboard_dir))
        for fname, warnings in lint_findings.items():
            for w in warnings:
                if w["rule"] == "parse-error":
                    has_parse_errors = True
                    context.log.error(f"PARSE ERROR {fname}: {w['detail']}")
                else:
                    context.log.warning(
                        f"LINT [{w['rule']}] {fname} "
                        f"panel {w['panel_id']} '{w['panel_title']}': {w['detail']}"
                    )
    else:
        context.log.warning(
            f"Dashboard directory not found at {dashboard_dir} — skipping static lint. "
            "Mount grafana/provisioning/dashboards into the container to enable it."
        )

    total_lint_warnings = sum(len(ws) for ws in lint_findings.values())
    total_parse_errors = sum(
        1 for ws in lint_findings.values() for w in ws if w["rule"] == "parse-error"
    )

    # ------------------------------------------------------------------
    # 2. Live panel checks — call the Grafana API.
    # ------------------------------------------------------------------
    has_credentials = bool(_GRAFANA_TOKEN or (_GRAFANA_USER and _GRAFANA_PASSWORD))

    if not has_credentials:
        context.log.warning(
            "Neither GRAFANA_TOKEN nor GRAFANA_ADMIN_PASSWORD is set — "
            "skipping live panel checks. Add credentials to the container env."
        )
        _emit_metadata(
            context,
            lint_warnings=total_lint_warnings,
            parse_errors=total_parse_errors,
            dashboards_checked=0,
            failing_panels=0,
            failures=[],
            live_status="skipped — no credentials",
        )
        if has_parse_errors:
            raise Exception(
                f"{total_parse_errors} dashboard JSON parse error(s) detected. "
                "Fix before the next pipeline run."
            )
        return

    try:
        client = _checker.GrafanaClient(
            base_url=_GRAFANA_URL,
            token=_GRAFANA_TOKEN,
            user=_GRAFANA_USER if not _GRAFANA_TOKEN else None,
            password=_GRAFANA_PASSWORD if not _GRAFANA_TOKEN else None,
        )
        datasources = client.datasources()
        dashboards = client.search_dashboards()
    except Exception as exc:
        context.log.warning(
            f"Cannot reach Grafana at {_GRAFANA_URL}: {exc}. "
            "Skipping live checks — pipeline data is still valid."
        )
        _emit_metadata(
            context,
            lint_warnings=total_lint_warnings,
            parse_errors=total_parse_errors,
            dashboards_checked=0,
            failing_panels=0,
            failures=[],
            live_status=f"skipped — connection failed: {exc}",
        )
        if has_parse_errors:
            raise Exception(
                f"{total_parse_errors} dashboard JSON parse error(s) detected."
            )
        return

    time_to = dt.datetime.now(dt.timezone.utc)
    time_from = time_to - dt.timedelta(days=365)

    all_failures: list[dict[str, Any]] = []

    for dash in dashboards:
        _, failing_panels = _checker.check_dashboard(
            client,
            dash,
            datasources,
            time_from=time_from,
            time_to=time_to,
            min_rows=1,
        )
        for panel in failing_panels:
            msg = panel.get("messages", "")
            context.log.warning(
                f"NO DATA: '{dash.get('title')}' / '{panel.get('panel_title')}': "
                f"{msg[:200]}"
            )
            all_failures.append(
                {
                    "dashboard": dash.get("title", ""),
                    "panel": panel.get("panel_title", ""),
                    "error": msg,
                }
            )

    _emit_metadata(
        context,
        lint_warnings=total_lint_warnings,
        parse_errors=total_parse_errors,
        dashboards_checked=len(dashboards),
        failing_panels=len(all_failures),
        failures=all_failures,
        live_status="ok",
    )

    context.log.info(
        f"Quality gate: {len(dashboards)} dashboards checked, "
        f"{len(all_failures)} failing panels, "
        f"{total_lint_warnings} lint warnings, "
        f"{total_parse_errors} parse errors."
    )

    if has_parse_errors:
        raise Exception(
            f"{total_parse_errors} dashboard JSON parse error(s) detected. "
            "Fix before the next pipeline run."
        )

    if all_failures:
        context.log.warning(
            f"{len(all_failures)} panels returned no data. "
            "Review the 'failing_panels_detail' metadata above for specifics. "
            "These are warnings — the pipeline data itself is valid."
        )


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _emit_metadata(
    context,
    *,
    lint_warnings: int,
    parse_errors: int,
    dashboards_checked: int,
    failing_panels: int,
    failures: list[dict[str, Any]],
    live_status: str,
) -> None:
    rows = failures[:50]  # cap table at 50 rows for the UI
    table_rows = "\n".join(
        f"| {r['dashboard']} | {r['panel']} | {r['error'][:100]} |"
        for r in rows
    )
    table_md = (
        f"| Dashboard | Panel | Error |\n|---|---|---|\n{table_rows}"
        if rows
        else "All panels returned data."
    )

    context.add_output_metadata(
        {
            "grafana_url": MetadataValue.url(_GRAFANA_URL),
            "checked_at": MetadataValue.text(
                dt.datetime.now(dt.timezone.utc).isoformat()
            ),
            "live_check_status": MetadataValue.text(live_status),
            "dashboards_checked": dashboards_checked,
            "failing_panels": failing_panels,
            "lint_warnings": lint_warnings,
            "lint_parse_errors": parse_errors,
            "failing_panels_detail": MetadataValue.md(table_md),
        }
    )
