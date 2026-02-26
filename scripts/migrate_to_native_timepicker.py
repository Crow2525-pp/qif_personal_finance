#!/usr/bin/env python3
"""Migrate all dashboard JSON files from custom time_window variable to native Grafana time picker.

This is a one-shot migration script for task 110.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

DASHBOARD_DIR = Path("grafana/provisioning/dashboards")

# --- Quick ranges presets by archetype ---

HISTORICAL_QUICK_RANGES = [
    {"from": "now-1M/M", "to": "now/M", "display": "Last complete month"},
    {"from": "now/Y", "to": "now", "display": "Year to date"},
    {"from": "now-12M/M", "to": "now/M", "display": "Trailing 12 months"},
]

FORWARD_QUICK_RANGES = [
    {"from": "now", "to": "now+12M", "display": "Next 12 months"},
    {"from": "now", "to": "now+5y", "display": "Next 5 years"},
]

HYBRID_QUICK_RANGES = [
    {"from": "now-12M", "to": "now+12M", "display": "Last 12 months + next 12 months"},
    {"from": "now-10y", "to": "now+5y", "display": "Full history + projections"},
]

FIXED_PERIOD_QUICK_RANGES = [
    {"from": "now-10y", "to": "now", "display": "Full history"},
]

# --- Dashboard classification ---

ARCHETYPE_MAP: dict[str, str] = {}  # populated from tags at runtime

EXCEPTION_TAGS = {
    "time_control:time_specific_exception",
    "time_control:no_time_component_exception",
    "time_control:forward_looking_exception",
    "time_control:hybrid_future_component_exception",
}


def get_archetype(tags: list[str]) -> str:
    for tag in tags:
        if tag.startswith("time_control_archetype:"):
            return tag.split(":", 1)[1]
    return "historical_windowed"


def get_exception_type(tags: list[str]) -> str | None:
    for tag in tags:
        if tag in EXCEPTION_TAGS:
            return tag
    return None


def remove_template_var(dashboard: dict, var_name: str) -> bool:
    """Remove a template variable by name. Returns True if removed."""
    tlist = dashboard.get("templating", {}).get("list", [])
    original_len = len(tlist)
    dashboard.setdefault("templating", {})["list"] = [
        v for v in tlist if v.get("name") != var_name
    ]
    return len(dashboard["templating"]["list"]) < original_len


def strip_var_from_urls(node: object, var_patterns: list[str]) -> int:
    """Recursively strip &var-xxx=... patterns from URL strings. Returns count of changes."""
    changes = 0
    if isinstance(node, dict):
        for key in list(node.keys()):
            if key == "url" and isinstance(node[key], str):
                original = node[key]
                for pattern in var_patterns:
                    node[key] = re.sub(pattern, "", node[key])
                if node[key] != original:
                    changes += 1
            else:
                changes += strip_var_from_urls(node[key], var_patterns)
    elif isinstance(node, list):
        for item in node:
            changes += strip_var_from_urls(item, var_patterns)
    return changes


def rewrite_executive_sql(sql: str) -> str:
    """Rewrite the executive dashboard CTE pattern from ${time_window} to $__timeFrom()/$__timeTo()."""

    # Replace the selected_period CTE that resolves 'Latest'
    # Pattern: selected_period AS (\n  SELECT CASE\n ... END AS month_date\n),
    sql = re.sub(
        r"selected_period\s+AS\s*\(\s*SELECT\s+CASE\s+"
        r"WHEN\s+'Latest'\s*=\s*'Latest'.*?END\s+AS\s+month_date\s*\)",
        "selected_period AS (\n  SELECT $__timeTo()::date AS month_date\n)",
        sql,
        flags=re.DOTALL,
    )

    # Replace the window_range CTE that uses CASE '${time_window}'
    sql = re.sub(
        r"window_range\s+AS\s*\(\s*SELECT\s+"
        r"CASE\s+'\$\{time_window\}'.*?END\s+AS\s+start_date,\s*"
        r"\(SELECT\s+month_date\s+FROM\s+selected_period\)\s+AS\s+end_date\s*\)",
        "window_range AS (\n  SELECT\n"
        "    $__timeFrom()::date AS start_date,\n"
        "    $__timeTo()::date AS end_date\n)",
        sql,
        flags=re.DOTALL,
    )

    # Replace display label CASE statements: CASE '${time_window}' WHEN 'ytd' THEN 'Year to Date' ...
    # These are used in SELECT for display text — replace with date range formatting
    sql = re.sub(
        r"CASE\s+'\$\{time_window\}'\s+"
        r"WHEN\s+'ytd'\s+THEN\s+'Year to Date'\s+"
        r"WHEN\s+'trailing_12m'\s+THEN\s+'Trailing 12 Months'\s+"
        r"ELSE\s+'Latest Month'\s*"
        r"END\s+AS\s+\"Time Window\"",
        "to_char($__timeFrom()::date, 'Mon YYYY') || ' – ' || to_char($__timeTo()::date, 'Mon YYYY') AS \"Time Window\"",
        sql,
        flags=re.DOTALL,
    )

    # Replace "Data Through" CASE statements
    sql = re.sub(
        r"CASE\s+'\$\{time_window\}'\s+"
        r"WHEN\s+'ytd'\s+THEN\s+to_char\(\(SELECT start_date FROM window_range\),\s*'Mon YYYY'\)\s*\|\|\s*' – '\s*\|\|\s*to_char\(\(SELECT end_date FROM window_range\),\s*'Mon YYYY'\)\s+"
        r"WHEN\s+'trailing_12m'\s+THEN\s+to_char\(\(SELECT start_date FROM window_range\),\s*'Mon YYYY'\)\s*\|\|\s*' – '\s*\|\|\s*to_char\(\(SELECT end_date FROM window_range\),\s*'Mon YYYY'\)\s+"
        r"ELSE\s+to_char\(\(SELECT end_date FROM window_range\),\s*'Mon YYYY'\)\s*"
        r"END\s+AS\s+\"Data Through\"",
        "to_char($__timeFrom()::date, 'Mon YYYY') || ' – ' || to_char($__timeTo()::date, 'Mon YYYY') AS \"Data Through\"",
        sql,
        flags=re.DOTALL,
    )

    # Replace period_label CASE statements (used in summary panels)
    sql = re.sub(
        r"CASE\s+'\$\{time_window\}'\s+"
        r"WHEN\s+'ytd'\s+THEN\s+'YTD through '\s*\|\|\s*to_char\(\(SELECT end_date FROM window_range\),\s*'Mon YYYY'\)\s+"
        r"WHEN\s+'trailing_12m'\s+THEN\s+'Trailing 12M through '\s*\|\|\s*to_char\(\(SELECT end_date FROM window_range\),\s*'Mon YYYY'\)\s+"
        r"ELSE\s+to_char\(\(SELECT end_date FROM window_range\),\s*'Mon YYYY'\)\s*"
        r"END\s+AS\s+period_label",
        "to_char($__timeFrom()::date, 'Mon YYYY') || ' – ' || to_char($__timeTo()::date, 'Mon YYYY') AS period_label",
        sql,
        flags=re.DOTALL,
    )

    return sql


def rewrite_sql_in_panels(node: object) -> int:
    """Recursively find rawSql fields and rewrite ${time_window} patterns. Returns change count."""
    changes = 0
    if isinstance(node, dict):
        if "rawSql" in node and isinstance(node["rawSql"], str) and "${time_window}" in node["rawSql"]:
            original = node["rawSql"]
            node["rawSql"] = rewrite_executive_sql(node["rawSql"])
            if node["rawSql"] != original:
                changes += 1
        for key, value in node.items():
            if key != "rawSql":
                changes += rewrite_sql_in_panels(value)
    elif isinstance(node, list):
        for item in node:
            changes += rewrite_sql_in_panels(item)
    return changes


def migrate_dashboard(file_path: Path) -> dict:
    """Migrate a single dashboard file. Returns a summary dict."""
    dashboard = json.loads(file_path.read_text(encoding="utf-8"))
    uid = dashboard.get("uid", file_path.stem)
    tags = [t for t in dashboard.get("tags", []) if isinstance(t, str)]
    archetype = get_archetype(tags)
    exception_type = get_exception_type(tags)

    summary = {"uid": uid, "file": file_path.name, "archetype": archetype, "changes": []}

    # 1. Remove time_window and dashboard_period template variables
    if remove_template_var(dashboard, "time_window"):
        summary["changes"].append("removed time_window variable")
    if remove_template_var(dashboard, "dashboard_period"):
        summary["changes"].append("removed dashboard_period variable")

    # 2. Strip var-time_window and var-dashboard_period from URLs
    url_patterns = [
        r"&var-time_window=\$\{time_window\}",
        r"&var-time_window=[^&\"]*",
        r"&var-dashboard_period=\$\{dashboard_period\}",
        r"&var-dashboard_period=[^&\"]*",
    ]
    url_changes = strip_var_from_urls(dashboard, url_patterns)
    if url_changes:
        summary["changes"].append(f"cleaned {url_changes} URLs")

    # 3. Rewrite SQL (only executive dashboard has ${time_window} in SQL)
    sql_changes = rewrite_sql_in_panels(dashboard.get("panels", []))
    if sql_changes:
        summary["changes"].append(f"rewrote {sql_changes} SQL queries")

    # 4. Set timepicker and time defaults based on archetype
    if archetype == "atemporal_no_time_component":
        dashboard["timepicker"] = {"hidden": True}
        summary["changes"].append("set timepicker.hidden=true")
    elif archetype == "forward_looking":
        dashboard["timepicker"] = {"hidden": False, "quick_ranges": FORWARD_QUICK_RANGES}
        dashboard["time"] = {"from": "now", "to": "now+5y"}
        summary["changes"].append("set forward_looking quick_ranges")
    elif archetype == "hybrid_past_future":
        dashboard["timepicker"] = {"hidden": False, "quick_ranges": HYBRID_QUICK_RANGES}
        dashboard["time"] = {"from": "now-10y", "to": "now+5y"}
        summary["changes"].append("set hybrid quick_ranges")
    elif archetype == "historical_fixed_period":
        dashboard["timepicker"] = {"hidden": False, "quick_ranges": FIXED_PERIOD_QUICK_RANGES}
        dashboard["time"] = {"from": "now-5y", "to": "now"}
        summary["changes"].append("set fixed_period quick_ranges")
    else:
        # historical_windowed (default)
        dashboard["timepicker"] = {"hidden": False, "quick_ranges": HISTORICAL_QUICK_RANGES}
        dashboard["time"] = {"from": "now-1M/M", "to": "now/M"}
        summary["changes"].append("set historical quick_ranges")

    # 5. Write back
    file_path.write_text(json.dumps(dashboard, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    return summary


def main() -> int:
    if not DASHBOARD_DIR.exists():
        print(f"ERROR: {DASHBOARD_DIR} not found")
        return 1

    files = sorted(DASHBOARD_DIR.glob("*.json"))
    print(f"Migrating {len(files)} dashboards...\n")

    for f in files:
        result = migrate_dashboard(f)
        changes = ", ".join(result["changes"]) if result["changes"] else "no changes"
        print(f"  [{result['archetype'][:20]:20s}] {result['uid']:40s} → {changes}")

    print(f"\nDone. Migrated {len(files)} dashboards.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
