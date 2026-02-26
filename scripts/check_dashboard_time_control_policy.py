#!/usr/bin/env python3
"""Validate dashboard time-control policy for task 110.

Enforces native Grafana time picker as the canonical time control:
- Non-atemporal dashboards must have timepicker.quick_ranges configured
- Atemporal dashboards must have timepicker.hidden = true
- No time_window or dashboard_period template variables allowed
- No var-time_window or var-dashboard_period in links
- Non-exception, non-fixed-period dashboards must reference $__timeFrom/$__timeTo in SQL
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Iterable

ARCHETYPE_PREFIX = "time_control_archetype:"
REASON_PREFIX = "time_control_reason:"

ALLOWED_ARCHETYPE_TAGS = {
    "time_control_archetype:historical_windowed",
    "time_control_archetype:historical_fixed_period",
    "time_control_archetype:atemporal_no_time_component",
    "time_control_archetype:forward_looking",
    "time_control_archetype:hybrid_past_future",
}
EXCEPTION_TAGS = {
    "time_control:time_specific_exception",
    "time_control:no_time_component_exception",
    "time_control:forward_looking_exception",
    "time_control:hybrid_future_component_exception",
}

HISTORICAL_QUICK_RANGES_DISPLAYS = {
    "Last complete month",
    "Year to date",
    "Trailing 12 months",
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate task-110 dashboard time-control policy (native time picker)."
    )
    parser.add_argument(
        "--dashboard-dir",
        default="grafana/provisioning/dashboards",
        help="Directory containing dashboard JSON files.",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="json_output",
        help="Emit machine-readable JSON output.",
    )
    return parser.parse_args()


def collect_urls(node: object) -> Iterable[str]:
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "url" and isinstance(value, str):
                yield value
            else:
                yield from collect_urls(value)
    elif isinstance(node, list):
        for item in node:
            yield from collect_urls(item)


def collect_panel_sql(node: object) -> Iterable[str]:
    """Yield rawSql / query strings from every panel target in the dashboard."""
    if isinstance(node, dict):
        for key in ("rawSql", "query"):
            if key in node and isinstance(node[key], str):
                yield node[key]
        for key, value in node.items():
            if key not in ("rawSql", "query"):
                yield from collect_panel_sql(value)
    elif isinstance(node, list):
        for item in node:
            yield from collect_panel_sql(item)


def collect_panel_sql_with_title(panels: list) -> Iterable[tuple[str, str]]:
    """Yield (panel_title, rawSql) for every panel target in the dashboard."""
    for panel in panels:
        if not isinstance(panel, dict):
            continue
        title = panel.get("title", "<untitled>")
        # Check targets in this panel
        for target in panel.get("targets", []):
            if isinstance(target, dict):
                for key in ("rawSql", "query"):
                    if key in target and isinstance(target[key], str) and target[key].strip():
                        yield (title, target[key])
        # Recurse into nested panels (rows/groups)
        for child in panel.get("panels", []):
            if isinstance(child, dict):
                child_title = child.get("title", title)
                for target in child.get("targets", []):
                    if isinstance(target, dict):
                        for key in ("rawSql", "query"):
                            if key in target and isinstance(target[key], str) and target[key].strip():
                                yield (child_title, target[key])


def references_time_macros(sql: str) -> bool:
    """Return True if the SQL string references Grafana time macros."""
    return "$__timeFrom" in sql or "$__timeTo" in sql or "$__timeFilter" in sql


def get_var(dashboard: dict, var_name: str) -> dict | None:
    for var in dashboard.get("templating", {}).get("list", []):
        if isinstance(var, dict) and var.get("name") == var_name:
            return var
    return None


def get_archetype(tags: list[str]) -> str | None:
    for tag in tags:
        if tag.startswith(ARCHETYPE_PREFIX):
            return tag.split(":", 1)[1]
    return None


def check_dashboard(dashboard: dict, file_path: Path) -> list[str]:
    """Check a single dashboard for policy violations. Returns list of violation messages."""
    violations: list[str] = []
    tags = [tag for tag in dashboard.get("tags", []) if isinstance(tag, str)]
    archetype_tags = [t for t in tags if t.startswith(ARCHETYPE_PREFIX)]
    exception_tags = [t for t in tags if t in EXCEPTION_TAGS]
    reason_tags = [t for t in tags if t.startswith(REASON_PREFIX)]
    archetype = get_archetype(tags)

    # Must have exactly one archetype tag
    if len(archetype_tags) != 1 or archetype_tags[0] not in ALLOWED_ARCHETYPE_TAGS:
        violations.append("must contain exactly one valid archetype tag")

    # Exception tag validation
    is_exception = len(exception_tags) > 0
    if is_exception:
        if len(exception_tags) != 1:
            violations.append("exception dashboards must contain exactly one exception class tag")
        if len(reason_tags) == 0:
            violations.append("exception dashboards must include time_control_reason:*")
    else:
        if reason_tags:
            violations.append("non-exception dashboards cannot include time_control_reason:*")

    # No time_window or dashboard_period template variables allowed
    if get_var(dashboard, "time_window") is not None:
        violations.append("time_window template variable must be removed (use native time picker)")
    if get_var(dashboard, "dashboard_period") is not None:
        violations.append("dashboard_period template variable must be removed")

    # No var-time_window or var-dashboard_period in links
    urls = list(collect_urls(dashboard))
    if any("var-time_window" in url for url in urls):
        violations.append("links must not contain var-time_window (use ${__url_time_range} only)")
    if any("var-dashboard_period" in url for url in urls):
        violations.append("links must not contain var-dashboard_period")

    # Timepicker checks by archetype
    timepicker = dashboard.get("timepicker", {})

    if archetype == "atemporal_no_time_component":
        # Must have timepicker hidden
        if timepicker.get("hidden") is not True:
            violations.append("atemporal dashboards must have timepicker.hidden = true")
    else:
        # Must NOT have timepicker hidden
        if timepicker.get("hidden") is True:
            violations.append("non-atemporal dashboards must not hide the time picker")

        # Must have quick_ranges configured
        quick_ranges = timepicker.get("quick_ranges", [])
        if not quick_ranges:
            violations.append("non-atemporal dashboards must have timepicker.quick_ranges configured")

        # Historical dashboards: check for canonical presets
        if archetype == "historical_windowed":
            displays = {qr.get("display", "") for qr in quick_ranges if isinstance(qr, dict)}
            missing = HISTORICAL_QUICK_RANGES_DISPLAYS - displays
            if missing:
                violations.append(f"historical dashboards missing quick_ranges: {missing}")

        # Every panel SQL must reference time macros (except fixed_period which uses static ranges)
        if archetype not in ("historical_fixed_period",):
            panels = dashboard.get("panels", [])
            for panel_title, sql in collect_panel_sql_with_title(panels):
                if not references_time_macros(sql):
                    violations.append(
                        f"panel \"{panel_title}\" query must reference $__timeFrom, $__timeTo, or $__timeFilter"
                    )

    return violations


def main() -> int:
    args = parse_args()
    dashboard_dir = Path(args.dashboard_dir)

    if not dashboard_dir.exists() or not dashboard_dir.is_dir():
        message = f"Dashboard directory not found: {dashboard_dir}"
        if args.json_output:
            print(
                json.dumps(
                    {"ok": False, "error": "directory_not_found", "detail": message},
                    indent=2,
                )
            )
        else:
            print(f"ERROR: {message}")
        return 2

    violations: list[dict] = []
    dashboards_checked = 0

    for file_path in sorted(dashboard_dir.glob("*.json")):
        if not file_path.is_file():
            continue
        try:
            dashboard = json.loads(file_path.read_text(encoding="utf-8"))
        except Exception as exc:
            if args.json_output:
                print(
                    json.dumps(
                        {
                            "ok": False,
                            "error": "parse_or_runtime_error",
                            "file": str(file_path),
                            "detail": str(exc),
                        },
                        indent=2,
                    )
                )
            else:
                print(f"ERROR: Failed to parse {file_path}: {exc}")
            return 2

        dashboards_checked += 1
        uid = dashboard.get("uid", file_path.stem)

        for message in check_dashboard(dashboard, file_path):
            violations.append({"file": str(file_path), "uid": uid, "message": message})

    summary = {
        "ok": len(violations) == 0,
        "dashboard_dir": str(dashboard_dir),
        "dashboards_checked": dashboards_checked,
        "violations": violations,
    }

    if args.json_output:
        print(json.dumps(summary, indent=2))
    else:
        if summary["ok"]:
            print(f"PASS: policy compliant across {dashboards_checked} dashboards.")
        else:
            print(
                f"FAIL: {len(violations)} policy violation(s) across {dashboards_checked} dashboards."
            )
            for violation in violations:
                print(f"- [{violation['uid']}] {violation['message']} ({violation['file']})")

    return 0 if summary["ok"] else 1


if __name__ == "__main__":
    sys.exit(main())
