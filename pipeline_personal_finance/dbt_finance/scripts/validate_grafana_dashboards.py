import argparse
import json
import os
import sys
from typing import Any, Dict, List

import duckdb


def load_dashboards(dashboards_dir: str) -> List[str]:
    dashboards = []
    for entry in os.listdir(dashboards_dir):
        if not entry.endswith(".json"):
            continue
        if entry.endswith(".json.pre_update"):
            continue
        dashboards.append(os.path.join(dashboards_dir, entry))
    return sorted(dashboards)


def extract_panels(node: Any) -> List[Dict[str, Any]]:
    panels = []
    if isinstance(node, dict):
        if "panels" in node and isinstance(node["panels"], list):
            for panel in node["panels"]:
                panels.extend(extract_panels(panel))
        if "targets" in node and isinstance(node["targets"], list):
            panels.append(node)
        for value in node.values():
            panels.extend(extract_panels(value))
    elif isinstance(node, list):
        for item in node:
            panels.extend(extract_panels(item))
    return panels


def normalize_sql(raw_sql: str) -> str:
    sql = raw_sql.strip()
    sql = sql.replace("${dashboard_period}", "Latest")
    sql = sql.replace("$scenario", "full_time")
    if sql.endswith(";"):
        sql = sql[:-1]
    return sql


def validate_queries(db_path: str, dashboards_dir: str, require_nonempty: bool) -> int:
    dashboards = load_dashboards(dashboards_dir)
    if not dashboards:
        print(f"No dashboards found in {dashboards_dir}")
        return 1

    con = duckdb.connect(db_path)
    failures = 0
    empty_results = 0
    total_queries = 0

    for dashboard_path in dashboards:
        with open(dashboard_path, "r", encoding="utf-8") as handle:
            dashboard = json.load(handle)

        panels = extract_panels(dashboard)
        for panel in panels:
            for target in panel.get("targets", []):
                raw_sql = target.get("rawSql")
                if not raw_sql:
                    continue
                total_queries += 1
                sql = normalize_sql(raw_sql)
                try:
                    rows = con.execute(sql).fetchall()
                except Exception as exc:
                    failures += 1
                    title = panel.get("title", "unknown")
                    print(f"FAIL: {os.path.basename(dashboard_path)}::{title}")
                    print(f"  Error: {exc}")
                    continue

                if len(rows) == 0:
                    empty_results += 1
                    if require_nonempty:
                        failures += 1
                        title = panel.get("title", "unknown")
                        print(f"FAIL (empty): {os.path.basename(dashboard_path)}::{title}")

    con.close()

    print("\nValidation summary")
    print(f"  Dashboards: {len(dashboards)}")
    print(f"  Queries: {total_queries}")
    print(f"  Empty results: {empty_results}")
    print(f"  Failures: {failures}")

    return 1 if failures else 0


def main() -> None:
    parser = argparse.ArgumentParser(description="Validate Grafana dashboard SQL against DuckDB.")
    parser.add_argument(
        "--db-path",
        default=os.path.join(
            "pipeline_personal_finance",
            "dbt_finance",
            "duckdb",
            "personal_finance.duckdb",
        ),
        help="DuckDB database path.",
    )
    parser.add_argument(
        "--dashboards-dir",
        default=os.path.join("grafana", "provisioning", "dashboards"),
        help="Grafana dashboards directory.",
    )
    parser.add_argument(
        "--require-nonempty",
        action="store_true",
        help="Fail when any query returns no rows.",
    )
    args = parser.parse_args()

    exit_code = validate_queries(args.db_path, args.dashboards_dir, args.require_nonempty)
    sys.exit(exit_code)


if __name__ == "__main__":
    main()
