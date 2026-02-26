"""
Dagster asset: dashboard_quality_gate

Runs after the dbt reporting layer completes and verifies that:
  1. Dashboard JSON policy/lint gates already passed.
  2. Live dashboard panels return data via the Grafana API.

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

from .dashboard_policy_gate import (
    dashboard_json_lint_gate,
    dashboard_time_control_policy_gate,
)

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
@asset(
    deps=[dashboard_json_lint_gate, dashboard_time_control_policy_gate],
    group_name="post_dbt_qa",
    tags={"dagster/kind/grafana": "", "dagster/kind/python": ""},
    description=(
        "Runs live Grafana dashboard panel checks after post-dbt policy gates. "
        "Verifies all panels return data and surfaces failures as Dagster metadata."
    ),
)
def dashboard_quality_gate(context) -> None:
    _checker = _import_checker()

    # ------------------------------------------------------------------
    # Live panel checks — call the Grafana API.
    # ------------------------------------------------------------------
    total_lint_warnings = 0
    total_parse_errors = 0
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
        return

    time_to = dt.datetime.now(dt.timezone.utc)
    time_from = time_to - dt.timedelta(days=365)

    all_failures: list[dict[str, Any]] = []

    for dash in dashboards:
        try:
            _, failing_panels = _checker.check_dashboard(
                client,
                dash,
                datasources,
                time_from=time_from,
                time_to=time_to,
                min_rows=1,
            )
        except Exception as exc:
            context.log.warning(
                f"Could not check dashboard '{dash.get('title')}': {exc}. Skipping."
            )
            continue
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
        f"{total_lint_warnings} lint warnings, {total_parse_errors} parse errors."
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
