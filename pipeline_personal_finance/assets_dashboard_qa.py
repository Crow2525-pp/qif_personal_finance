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

from dagster import Failure, MetadataValue, asset

from .dashboard_policy_gate import (
    dashboard_json_lint_gate,
    dashboard_time_control_policy_gate,
)

_REPO_ROOT = Path(__file__).resolve().parents[1]
_SCRIPTS_DIR = _REPO_ROOT / "scripts"


def _import_checker():
    """Import check_grafana_dashboards lazily to avoid sys.path pollution at module load."""
    if str(_SCRIPTS_DIR) not in sys.path:
        sys.path.insert(0, str(_SCRIPTS_DIR))
    import check_grafana_dashboards as _mod
    return _mod

# ---------------------------------------------------------------------------
# Configuration — all overridable via environment variables.
# Inside Docker the internal service URL is used; externally GRAFANA_URL wins.
# ---------------------------------------------------------------------------
_GRAFANA_URL = os.environ.get("GRAFANA_URL", "http://grafana:3000")
_GRAFANA_TOKEN = os.environ.get("GRAFANA_TOKEN")
# GRAFANA_ADMIN_USER is the Grafana web app admin account (default: "admin").
# This is distinct from GRAFANA_USER which is the PostgreSQL datasource reader account.
_GRAFANA_USER = os.environ.get("GRAFANA_ADMIN_USER", "admin")
_GRAFANA_PASSWORD = os.environ.get("GRAFANA_ADMIN_PASSWORD")
_DASHBOARD_TIME_PICKER_RANGES = os.environ.get("DASHBOARD_TIME_PICKER_RANGES", "7,30,90,365")
_DASHBOARD_QUALITY_WARN_ONLY = os.environ.get("DASHBOARD_QUALITY_WARN_ONLY", "").strip().lower() in {
    "1",
    "true",
    "yes",
    "on",
}


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
        raise Failure(
            "dashboard_quality_gate requires Grafana credentials. "
            "Set GRAFANA_TOKEN or both GRAFANA_ADMIN_USER and GRAFANA_ADMIN_PASSWORD.",
            metadata={"grafana_url": MetadataValue.url(_GRAFANA_URL)},
        )

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
        raise Failure(
            f"Cannot reach Grafana at {_GRAFANA_URL}: {exc}. "
            "Ensure Grafana is running and GRAFANA_URL is correct.",
            metadata={"grafana_url": MetadataValue.url(_GRAFANA_URL), "error": str(exc)},
        ) from exc

    try:
        range_days = _checker.parse_time_picker_ranges(_DASHBOARD_TIME_PICKER_RANGES)
    except ValueError as exc:
        raise Failure(
            "dashboard_quality_gate configuration invalid",
            metadata={"dashboard_time_picker_ranges": _DASHBOARD_TIME_PICKER_RANGES, "error": str(exc)},
        ) from exc
    fallback_windows = _checker.build_time_windows(range_days)

    all_failures: list[dict[str, Any]] = []
    checked_window_labels: set[str] = set()

    for dash in dashboards:
        try:
            dashboard_data = client.dashboard(dash["uid"])
            dashboard_windows = _checker.dashboard_quick_range_windows(dashboard_data)
            time_windows = dashboard_windows if dashboard_windows else fallback_windows
            checked_window_labels.update(window[0] for window in time_windows)

            check_result = _checker.check_dashboard_across_time_windows(
                client,
                dash,
                datasources,
                time_windows=time_windows,
                min_rows=1,
                dashboard_data=dashboard_data,
            )
        except Exception as exc:
            context.log.warning(
                f"Could not check dashboard '{dash.get('title')}': {exc}"
            )
            all_failures.append(
                {
                    "dashboard": dash.get("title", ""),
                    "panel": "(dashboard-level error)",
                    "error": f"Check failed: {exc}",
                }
            )
            continue
        for by_window in check_result.get("by_time_window", []):
            time_window = by_window.get("time_window", "unknown")
            for panel in by_window.get("failing_panels", []):
                msg = panel.get("messages", "")
                context.log.warning(
                    f"NO DATA: '{dash.get('title')}' / '{panel.get('panel_title')}' / "
                    f"[{time_window}]: {msg[:200]}"
                )
                all_failures.append(
                    {
                        "dashboard": dash.get("title", ""),
                        "panel": panel.get("panel_title", ""),
                        "error": f"[{time_window}] {msg}",
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
        checked_time_windows=sorted(checked_window_labels),
    )

    context.log.info(
        f"Quality gate: {len(dashboards)} dashboards checked, "
        f"{len(all_failures)} failing panels, "
        f"{total_lint_warnings} lint warnings, {total_parse_errors} parse errors."
    )

    if all_failures:
        message = (
            f"{len(all_failures)} panel/time-window checks failed. "
            "Review 'failing_panels_detail' metadata for specifics."
        )
        if _DASHBOARD_QUALITY_WARN_ONLY:
            context.log.warning(
                f"{message} Continuing due to DASHBOARD_QUALITY_WARN_ONLY=true."
            )
        else:
            raise Failure(
                message,
                metadata={
                    "dashboards_checked": len(dashboards),
                    "failing_panels": len(all_failures),
                    "dashboard_time_picker_ranges": _DASHBOARD_TIME_PICKER_RANGES,
                },
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
    checked_time_windows: list[str],
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
            "checked_time_windows": checked_time_windows,
            "failing_panels_detail": MetadataValue.md(table_md),
        }
    )
