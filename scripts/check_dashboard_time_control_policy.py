#!/usr/bin/env python3
"""Validate dashboard time-control policy for task 110."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Iterable

CANONICAL_QUERY = "latest_month,ytd,trailing_12m"
CANONICAL_VALUES = ["latest_month", "ytd", "trailing_12m"]
CANONICAL_LABELS = ["Last Complete Month", "Year to Date", "Trailing 12 Months"]

ROLL_OUT_PREFIX = "time_control_rollout:"
ARCHETYPE_PREFIX = "time_control_archetype:"
REASON_PREFIX = "time_control_reason:"

ALLOWED_ROLLOUT_TAGS = {
    "time_control_rollout:tranche_a",
    "time_control_rollout:tranche_b",
}
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate task-110 dashboard time-control policy."
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
    parser.add_argument(
        "--strict",
        action=argparse.BooleanOptionalAction,
        default=True,
        help="Enforce canonical display labels for time_window options.",
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


def get_var(dashboard: dict, var_name: str) -> dict | None:
    for var in dashboard.get("templating", {}).get("list", []):
        if isinstance(var, dict) and var.get("name") == var_name:
            return var
    return None


def check_canonical_time_window(dashboard: dict, strict: bool) -> list[str]:
    violations: list[str] = []
    time_window = get_var(dashboard, "time_window")
    if time_window is None:
        return ["missing canonical time_window variable"]

    if time_window.get("type") != "custom":
        violations.append("time_window must be type=custom")
    if time_window.get("query") != CANONICAL_QUERY:
        violations.append(f"time_window query must equal '{CANONICAL_QUERY}'")
    if time_window.get("multi") is not False:
        violations.append("time_window multi must be false")
    if time_window.get("includeAll") is not False:
        violations.append("time_window includeAll must be false")
    if time_window.get("skipUrlSync") is not False:
        violations.append("time_window skipUrlSync must be false")

    options = time_window.get("options", [])
    values = [item.get("value") for item in options if isinstance(item, dict)]
    if values != CANONICAL_VALUES:
        violations.append(f"time_window option values must be {CANONICAL_VALUES}")

    current_value = (time_window.get("current") or {}).get("value")
    if current_value != "latest_month":
        violations.append("time_window default current value must be latest_month")

    if strict:
        labels = [item.get("text") for item in options if isinstance(item, dict)]
        if labels != CANONICAL_LABELS:
            violations.append(f"time_window option labels must be {CANONICAL_LABELS}")
        current_text = (time_window.get("current") or {}).get("text")
        if current_text != "Last Complete Month":
            violations.append(
                "time_window default current text must be Last Complete Month"
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
        tags = [tag for tag in dashboard.get("tags", []) if isinstance(tag, str)]

        rollout_tags = [t for t in tags if t.startswith(ROLL_OUT_PREFIX)]
        archetype_tags = [t for t in tags if t.startswith(ARCHETYPE_PREFIX)]
        exception_tags = [t for t in tags if t in EXCEPTION_TAGS]
        reason_tags = [t for t in tags if t.startswith(REASON_PREFIX)]

        def add_violation(message: str) -> None:
            violations.append({"file": str(file_path), "uid": uid, "message": message})

        if len(rollout_tags) != 1 or rollout_tags[0] not in ALLOWED_ROLLOUT_TAGS:
            add_violation(
                "must contain exactly one valid rollout tag (time_control_rollout:tranche_a|tranche_b)"
            )
        if len(archetype_tags) != 1 or archetype_tags[0] not in ALLOWED_ARCHETYPE_TAGS:
            add_violation("must contain exactly one valid archetype tag")

        is_exception = len(exception_tags) > 0
        if is_exception:
            if len(exception_tags) != 1:
                add_violation(
                    "exception dashboards must contain exactly one exception class tag"
                )
            if len(reason_tags) == 0:
                add_violation("exception dashboards must include time_control_reason:*")
        else:
            if reason_tags:
                add_violation("non-exception dashboards cannot include time_control_reason:*")
            for message in check_canonical_time_window(dashboard, strict=args.strict):
                add_violation(message)

            if get_var(dashboard, "dashboard_period") is not None:
                add_violation("dashboard_period variable is not allowed")

            urls = list(collect_urls(dashboard))
            if any("var-dashboard_period=" in url for url in urls):
                add_violation("links must not forward var-dashboard_period")
            if any("/d/" in url and "var-time_window=" not in url for url in urls):
                add_violation("dashboard links must include var-time_window")

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
