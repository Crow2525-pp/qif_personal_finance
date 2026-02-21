#!/usr/bin/env python3
"""
Run dashboard QA checks (lint + live API + optional Playwright screenshots)
and persist a timestamped artifact bundle.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import subprocess
import sys
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_CHECKER = ROOT / "scripts" / "check_grafana_dashboards.py"
DEFAULT_REFERENCE = ROOT / ".claude" / "references" / "dashboard-llm-reference.md"
DEFAULT_OUTPUT_ROOT = ROOT / "artifacts" / "dashboard-quality"


@dataclass
class CommandResult:
    command: list[str]
    returncode: int
    stdout: str
    stderr: str


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Run dashboard QA quality gate: static lint, live Grafana checks, and "
            "optional Playwright screenshots."
        )
    )
    parser.add_argument(
        "--dashboards",
        nargs="*",
        default=[],
        help=(
            "Dashboard selectors (UID/title substrings) passed to checker as "
            "--dashboard <selector>."
        ),
    )
    parser.add_argument(
        "--lint-only",
        action="store_true",
        help="Run only static lint checks and skip live API checks/screenshots.",
    )
    parser.add_argument(
        "--screenshots",
        action="store_true",
        help="Capture Playwright screenshot evidence for selected dashboards.",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=365,
        help="Live check time window in days (default: 365).",
    )
    parser.add_argument(
        "--min-rows",
        type=int,
        default=1,
        help="Minimum rows/points expected by live panel checks (default: 1).",
    )
    parser.add_argument(
        "--checker-script",
        default=str(DEFAULT_CHECKER),
        help="Path to scripts/check_grafana_dashboards.py.",
    )
    parser.add_argument(
        "--reference-file",
        default=str(DEFAULT_REFERENCE),
        help="Path to markdown file listing Playwright review URLs.",
    )
    parser.add_argument(
        "--output-root",
        default=str(DEFAULT_OUTPUT_ROOT),
        help="Root folder for timestamped QA artifacts.",
    )
    parser.add_argument(
        "--max-failing-panels",
        type=int,
        default=0,
        help="Fail if total failing panels exceed this threshold (default: 0).",
    )
    parser.add_argument(
        "--max-layout-warnings",
        type=int,
        default=0,
        help="Fail if layout warning count exceeds this threshold (default: 0).",
    )
    parser.add_argument(
        "--max-static-warnings",
        type=int,
        default=0,
        help="Fail if static warning count exceeds this threshold (default: 0).",
    )
    parser.add_argument(
        "--max-parity-warnings",
        type=int,
        default=0,
        help="Fail if parity warning count exceeds this threshold (default: 0).",
    )
    parser.add_argument(
        "--max-screenshot-errors",
        type=int,
        default=0,
        help="Fail if screenshot capture errors exceed this threshold (default: 0).",
    )
    parser.add_argument(
        "--base-url",
        default=os.environ.get("GRAFANA_URL", "http://localhost:3001"),
        help="Grafana base URL (default from GRAFANA_URL or http://localhost:3001).",
    )
    parser.add_argument(
        "--headless",
        default="true",
        choices=["true", "false"],
        help="Run Playwright browser headless (default: true).",
    )
    return parser.parse_args()


def run_command(command: list[str]) -> CommandResult:
    proc = subprocess.run(command, capture_output=True, text=True, encoding="utf-8", errors="replace")
    return CommandResult(command=command, returncode=proc.returncode, stdout=proc.stdout, stderr=proc.stderr)


def write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def write_json(path: Path, payload: Any) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def try_parse_json(text: str) -> dict[str, Any]:
    try:
        loaded = json.loads(text)
        if isinstance(loaded, dict):
            return loaded
    except json.JSONDecodeError:
        pass
    return {}


def parse_reference_urls(reference_file: Path, selectors: list[str]) -> list[str]:
    if not reference_file.exists():
        return []

    urls: list[str] = []
    for line in reference_file.read_text(encoding="utf-8", errors="replace").splitlines():
        m = re.search(r"-\s+`(/d/[^`]+)`", line.strip())
        if m:
            urls.append(m.group(1))

    if not selectors:
        return urls

    lowered = [s.lower() for s in selectors]

    def keep(path: str) -> bool:
        value = path.lower()
        return any(sel in value for sel in lowered)

    filtered = [u for u in urls if keep(u)]
    return filtered if filtered else urls


def normalize_findings(
    lint_json: dict[str, Any] | None,
    live_json: dict[str, Any] | None,
    screenshot_results: list[dict[str, Any]] | None,
) -> list[dict[str, Any]]:
    findings: list[dict[str, Any]] = []

    lint_json = lint_json or {}
    live_json = live_json or {}
    screenshot_results = screenshot_results or []

    if lint_json.get("mode") == "lint-only":
        for file_name, warnings in (lint_json.get("files") or {}).items():
            for warning in warnings or []:
                findings.append(
                    {
                        "source": "lint",
                        "severity": "error" if warning.get("rule") == "parse-error" else "warning",
                        "dashboard": file_name,
                        "panel_id": warning.get("panel_id"),
                        "panel_title": warning.get("panel_title"),
                        "rule": warning.get("rule", "unknown"),
                        "message": warning.get("detail", ""),
                    }
                )

    for dash in live_json.get("dashboards") or []:
        title = dash.get("dashboard")
        uid = dash.get("uid")
        label = f"{title} ({uid})" if uid else str(title)

        for failure in dash.get("failing_panels") or []:
            findings.append(
                {
                    "source": "live",
                    "severity": "error",
                    "dashboard": label,
                    "panel_id": failure.get("panel_id"),
                    "panel_title": failure.get("panel_title"),
                    "rule": "no-data-or-error",
                    "message": failure.get("messages", ""),
                }
            )

        for warning in dash.get("layout_lint") or []:
            findings.append(
                {
                    "source": "layout",
                    "severity": "warning",
                    "dashboard": label,
                    "panel_id": warning.get("panel_id"),
                    "panel_title": warning.get("panel_title"),
                    "rule": "layout-lint",
                    "message": warning.get("message")
                    or f"len={warning.get('title_len') or warning.get('content_len')} allowed~{warning.get('allowed') or warning.get('allowed_lines')}",
                }
            )

        for warning in dash.get("static_warnings") or []:
            findings.append(
                {
                    "source": "static",
                    "severity": "warning",
                    "dashboard": label,
                    "panel_id": warning.get("panel_id"),
                    "panel_title": warning.get("panel_title"),
                    "rule": warning.get("rule", "static-warning"),
                    "message": warning.get("detail", ""),
                }
            )

        for warning in dash.get("parity_warnings") or []:
            findings.append(
                {
                    "source": "parity",
                    "severity": "warning",
                    "dashboard": label,
                    "panel_id": warning.get("panel_id"),
                    "panel_title": warning.get("panel_title"),
                    "rule": "mobile-parity",
                    "message": warning.get("message", ""),
                }
            )

    for result in screenshot_results:
        if result.get("status") == "error":
            findings.append(
                {
                    "source": "playwright",
                    "severity": "error",
                    "dashboard": result.get("path", "unknown"),
                    "panel_id": None,
                    "panel_title": None,
                    "rule": "screenshot-capture-failed",
                    "message": result.get("message", "unknown screenshot error"),
                }
            )

    return findings


def render_summary(
    args: argparse.Namespace,
    run_dir: Path,
    lint_result: CommandResult,
    live_result: CommandResult | None,
    lint_json: dict[str, Any],
    live_json: dict[str, Any] | None,
    screenshot_results: list[dict[str, Any]],
    findings: list[dict[str, Any]],
    gate_failed: bool,
    gate_reasons: list[str],
) -> str:
    failing_panels = int((live_json or {}).get("total_failing_panels", 0))
    layout = int((live_json or {}).get("total_layout_warnings", 0))
    static = int((live_json or {}).get("total_static_warnings", 0))
    parity = int((live_json or {}).get("total_parity_warnings", 0))
    lint_warnings = int(lint_json.get("total_warnings", 0))
    screenshot_errors = sum(1 for item in screenshot_results if item.get("status") == "error")

    lines: list[str] = []
    lines.append("# Dashboard Quality Gate Report")
    lines.append("")
    lines.append(f"- Timestamp (UTC): {dt.datetime.now(dt.timezone.utc).isoformat()}")
    lines.append(f"- Output directory: `{run_dir}`")
    lines.append(f"- Base URL: `{args.base_url}`")
    lines.append(f"- Dashboards filter: `{', '.join(args.dashboards) if args.dashboards else 'ALL'}`")
    lines.append(f"- Lint only: `{args.lint_only}`")
    lines.append(f"- Screenshots enabled: `{args.screenshots and (not args.lint_only)}`")
    lines.append("")
    lines.append("## Status")
    lines.append("")
    lines.append(f"- Gate result: `{'FAIL' if gate_failed else 'PASS'}`")
    if gate_reasons:
        for reason in gate_reasons:
            lines.append(f"- Reason: {reason}")
    lines.append("")
    lines.append("## Counts")
    lines.append("")
    lines.append(f"- Static lint warnings (file scan): `{lint_warnings}`")
    lines.append(f"- Live failing panels: `{failing_panels}`")
    lines.append(f"- Live layout warnings: `{layout}`")
    lines.append(f"- Live static warnings: `{static}`")
    lines.append(f"- Live parity warnings: `{parity}`")
    lines.append(f"- Screenshot errors: `{screenshot_errors}`")
    lines.append(f"- Normalized findings: `{len(findings)}`")
    lines.append("")
    lines.append("## Command Exit Codes")
    lines.append("")
    lines.append(f"- lint checker: `{lint_result.returncode}`")
    lines.append(f"- live checker: `{live_result.returncode if live_result is not None else 'skipped'}`")
    lines.append("")

    if screenshot_results:
        lines.append("## Screenshot Results")
        lines.append("")
        for item in screenshot_results:
            if item.get("status") == "ok":
                lines.append(f"- OK `{item.get('path')}` -> `{item.get('file')}`")
            else:
                lines.append(f"- ERROR `{item.get('path')}`: {item.get('message')}")
        lines.append("")

    lines.append("## Artifact Files")
    lines.append("")
    lines.append("- `lint-only.json`")
    lines.append("- `lint-only.stdout.txt`")
    lines.append("- `lint-only.stderr.txt`")
    if live_result is not None:
        lines.append("- `live-checks.json`")
        lines.append("- `live-checks.stdout.txt`")
        lines.append("- `live-checks.stderr.txt`")
    lines.append("- `findings.normalized.json`")
    lines.append("- `report.md`")
    if screenshot_results:
        lines.append("- `screenshots/*`")

    return "\n".join(lines) + "\n"


def capture_screenshots(
    base_url: str,
    relative_paths: list[str],
    output_dir: Path,
    headless: bool,
) -> list[dict[str, Any]]:
    if not relative_paths:
        return []

    try:
        from playwright.sync_api import sync_playwright
    except Exception as exc:  # pragma: no cover - dependency/runtime branch
        return [{"status": "error", "path": "(all)", "message": f"Playwright unavailable: {exc}"}]

    user = os.environ.get("GRAFANA_USER", "admin")
    password = os.environ.get("GRAFANA_PASSWORD")

    output_dir.mkdir(parents=True, exist_ok=True)
    results: list[dict[str, Any]] = []

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=headless)
        context = browser.new_context()
        page = context.new_page()

        page.goto(base_url, wait_until="domcontentloaded", timeout=45000)

        # Best-effort login for standard Grafana login page.
        if page.locator("input[name='user']").count() > 0 and page.locator("input[name='password']").count() > 0:
            if not password:
                results.append(
                    {
                        "status": "error",
                        "path": "login",
                        "message": "GRAFANA_PASSWORD is not set; cannot log in for screenshot capture.",
                    }
                )
                browser.close()
                return results

            page.fill("input[name='user']", user)
            page.fill("input[name='password']", password)
            page.click("button[type='submit']")
            page.wait_for_timeout(1500)

        for rel_path in relative_paths:
            target = f"{base_url.rstrip('/')}{rel_path}"
            safe_name = rel_path.strip("/").replace("/", "_").replace("?", "_").replace("&", "_")
            file_path = output_dir / f"{safe_name}.png"
            try:
                page.goto(target, wait_until="domcontentloaded", timeout=45000)
                page.wait_for_timeout(1500)
                page.screenshot(path=str(file_path), full_page=True)
                results.append({"status": "ok", "path": rel_path, "file": str(file_path)})
            except Exception as exc:  # pragma: no cover - runtime diagnostics
                results.append({"status": "error", "path": rel_path, "message": str(exc)})

        browser.close()

    return results


def evaluate_gate(
    args: argparse.Namespace,
    lint_result: CommandResult,
    live_result: CommandResult | None,
    live_json: dict[str, Any] | None,
    lint_json: dict[str, Any],
    screenshot_results: list[dict[str, Any]],
) -> tuple[bool, list[str]]:
    reasons: list[str] = []

    if not lint_json:
        reasons.append("lint checker JSON output could not be parsed")
    if lint_result.returncode != 0 and not lint_json:
        reasons.append(f"lint checker command failed (exit {lint_result.returncode})")
    if lint_json.get("has_errors"):
        reasons.append("dashboard JSON parse-error findings detected in lint scan")

    live = live_json or {}
    if live_result is not None:
        if not live_json:
            reasons.append("live checker JSON output could not be parsed")
        if live_result.returncode != 0 and not live_json:
            reasons.append(f"live checker command failed (exit {live_result.returncode})")

    failing_panels = int(live.get("total_failing_panels", 0))
    layout = int(live.get("total_layout_warnings", 0))
    static = int(live.get("total_static_warnings", 0))
    parity = int(live.get("total_parity_warnings", 0))
    screenshot_errors = sum(1 for item in screenshot_results if item.get("status") == "error")

    if failing_panels > args.max_failing_panels:
        reasons.append(f"failing panels {failing_panels} > threshold {args.max_failing_panels}")
    if layout > args.max_layout_warnings:
        reasons.append(f"layout warnings {layout} > threshold {args.max_layout_warnings}")
    if static > args.max_static_warnings:
        reasons.append(f"static warnings {static} > threshold {args.max_static_warnings}")
    if parity > args.max_parity_warnings:
        reasons.append(f"parity warnings {parity} > threshold {args.max_parity_warnings}")
    if screenshot_errors > args.max_screenshot_errors:
        reasons.append(f"screenshot errors {screenshot_errors} > threshold {args.max_screenshot_errors}")

    return (len(reasons) > 0), reasons


def main() -> int:
    args = parse_args()

    checker_script = Path(args.checker_script)
    if not checker_script.exists():
        print(f"Checker script not found: {checker_script}", file=sys.stderr)
        return 2

    now = dt.datetime.now(dt.timezone.utc)
    run_id = f"{now.strftime('%Y%m%dT%H%M%S')}_{now.microsecond:06d}Z_{uuid.uuid4().hex[:8]}"
    run_dir = Path(args.output_root) / run_id
    run_dir.mkdir(parents=True, exist_ok=True)

    lint_cmd = [sys.executable, str(checker_script), "--lint-only", "--json"]
    lint_result = run_command(lint_cmd)

    write_text(run_dir / "lint-only.stdout.txt", lint_result.stdout)
    write_text(run_dir / "lint-only.stderr.txt", lint_result.stderr)

    lint_json = try_parse_json(lint_result.stdout)
    write_json(run_dir / "lint-only.json", lint_json or {"parse_error": "Could not parse lint-only JSON output."})

    live_result: CommandResult | None = None
    live_json: dict[str, Any] | None = None

    if not args.lint_only:
        live_cmd = [
            sys.executable,
            str(checker_script),
            "--json",
            "--days",
            str(args.days),
            "--min-rows",
            str(args.min_rows),
            "--base-url",
            args.base_url,
        ]

        for selector in args.dashboards:
            live_cmd.extend(["--dashboard", selector])

        live_result = run_command(live_cmd)
        write_text(run_dir / "live-checks.stdout.txt", live_result.stdout)
        write_text(run_dir / "live-checks.stderr.txt", live_result.stderr)
        live_json = try_parse_json(live_result.stdout)
        write_json(run_dir / "live-checks.json", live_json or {"parse_error": "Could not parse live-check JSON output."})

    screenshot_results: list[dict[str, Any]] = []
    if args.screenshots and not args.lint_only:
        reference_paths = parse_reference_urls(Path(args.reference_file), args.dashboards)
        screenshot_results = capture_screenshots(
            base_url=args.base_url,
            relative_paths=reference_paths,
            output_dir=run_dir / "screenshots",
            headless=args.headless == "true",
        )
        write_json(run_dir / "screenshots.json", screenshot_results)

    findings = normalize_findings(lint_json, live_json, screenshot_results)
    write_json(run_dir / "findings.normalized.json", findings)

    gate_failed, gate_reasons = evaluate_gate(
        args,
        lint_result,
        live_result,
        live_json,
        lint_json,
        screenshot_results,
    )

    report = render_summary(
        args=args,
        run_dir=run_dir,
        lint_result=lint_result,
        live_result=live_result,
        lint_json=lint_json,
        live_json=live_json,
        screenshot_results=screenshot_results,
        findings=findings,
        gate_failed=gate_failed,
        gate_reasons=gate_reasons,
    )
    write_text(run_dir / "report.md", report)

    print(f"Dashboard quality gate artifacts written to: {run_dir}")
    print(f"Gate result: {'FAIL' if gate_failed else 'PASS'}")
    if gate_reasons:
        for reason in gate_reasons:
            print(f"- {reason}")

    return 1 if gate_failed else 0


if __name__ == "__main__":
    sys.exit(main())
