#!/usr/bin/env python3
"""Validate Grafana dashboard JSON parseability."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Validate that dashboard JSON files are parseable."
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

    failures: list[dict] = []
    files = sorted(p for p in dashboard_dir.glob("*.json") if p.is_file())

    for file_path in files:
        try:
            with file_path.open("r", encoding="utf-8") as handle:
                json.load(handle)
        except json.JSONDecodeError as exc:
            failures.append(
                {
                    "file": str(file_path),
                    "line": exc.lineno,
                    "column": exc.colno,
                    "message": exc.msg,
                }
            )
        except OSError as exc:
            if args.json_output:
                print(
                    json.dumps(
                        {"ok": False, "error": "runtime_error", "detail": str(exc)},
                        indent=2,
                    )
                )
            else:
                print(f"ERROR: Failed to read {file_path}: {exc}")
            return 2

    if args.json_output:
        print(
            json.dumps(
                {
                    "ok": not failures,
                    "dashboard_dir": str(dashboard_dir),
                    "files_checked": len(files),
                    "failures": failures,
                },
                indent=2,
            )
        )
    else:
        if not failures:
            print(f"PASS: {len(files)} dashboard JSON files parsed successfully.")
        else:
            print(
                f"FAIL: {len(failures)} of {len(files)} dashboard JSON files failed parsing."
            )
            for failure in failures:
                print(
                    f"- {failure['file']}:{failure['line']}:{failure['column']} {failure['message']}"
                )

    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
