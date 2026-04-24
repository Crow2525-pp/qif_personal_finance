from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

from dagster import Failure, MetadataValue, Output, asset

from .assets import finance_dbt_assets

REPO_ROOT = Path(__file__).resolve().parents[1]


def _warn_only_enabled() -> bool:
    return os.getenv("DASHBOARD_POLICY_GATE_WARN_ONLY", "").strip().lower() in {
        "1",
        "true",
        "yes",
        "on",
    }


def _run_script(script_name: str, extra_args: list[str] | None = None) -> subprocess.CompletedProcess[str]:
    args = [sys.executable, str(REPO_ROOT / "scripts" / script_name)]
    if extra_args:
        args.extend(extra_args)
    return subprocess.run(args, cwd=REPO_ROOT, capture_output=True, text=True, check=False)


def _metadata_from_result(result: subprocess.CompletedProcess[str]) -> dict:
    payload = {
        "exit_code": result.returncode,
        "stdout": result.stdout.strip(),
        "stderr": result.stderr.strip(),
    }
    try:
        parsed = json.loads(result.stdout) if result.stdout.strip() else {}
    except json.JSONDecodeError:
        parsed = {}

    metadata = {"exit_code": payload["exit_code"]}
    if parsed:
        metadata["summary"] = MetadataValue.json(parsed)
    if payload["stdout"]:
        metadata["stdout"] = MetadataValue.md(f"```\n{payload['stdout']}\n```")
    if payload["stderr"]:
        metadata["stderr"] = MetadataValue.md(f"```\n{payload['stderr']}\n```")
    return metadata


@asset(
    deps=[finance_dbt_assets],
    group_name="post_dbt_qa",
    description="Single post-dbt readiness anchor for downstream dashboard QA gates.",
)
def post_dbt_reporting_ready() -> Output[dict]:
    return Output({"ready": True})


@asset(
    deps=[post_dbt_reporting_ready],
    group_name="post_dbt_qa",
    description="Validates Grafana dashboard JSON parseability before policy checks.",
)
def dashboard_json_lint_gate(context) -> Output[dict]:
    warn_only = _warn_only_enabled()
    result = _run_script("validate_dashboard_json.py", ["--json"])
    metadata = _metadata_from_result(result)
    metadata["warn_only"] = warn_only

    if result.returncode == 2:
        raise Failure("dashboard_json_lint_gate runtime failure", metadata=metadata)
    if result.returncode != 0 and not warn_only:
        raise Failure("dashboard_json_lint_gate failed", metadata=metadata)
    if result.returncode != 0 and warn_only:
        context.log.warning(
            "dashboard_json_lint_gate violations found but continuing due to DASHBOARD_POLICY_GATE_WARN_ONLY=true"
        )

    return Output({"exit_code": result.returncode, "warn_only": warn_only}, metadata=metadata)


@asset(
    deps=[dashboard_json_lint_gate],
    group_name="post_dbt_qa",
    description=(
        "Detects non-ASCII characters (smart quotes, en/em dashes, bullets, "
        "Greek letters) that render as mojibake when encoding is mishandled."
    ),
)
def dashboard_encoding_gate(context) -> Output[dict]:
    warn_only = _warn_only_enabled()
    result = _run_script("check_dashboard_encoding.py", ["--json"])
    metadata = _metadata_from_result(result)
    metadata["warn_only"] = warn_only

    if result.returncode == 2:
        raise Failure("dashboard_encoding_gate runtime failure", metadata=metadata)
    if result.returncode != 0 and not warn_only:
        raise Failure("dashboard_encoding_gate failed", metadata=metadata)
    if result.returncode != 0 and warn_only:
        context.log.warning(
            "dashboard_encoding_gate violations found but continuing due to DASHBOARD_POLICY_GATE_WARN_ONLY=true"
        )

    return Output({"exit_code": result.returncode, "warn_only": warn_only}, metadata=metadata)


@asset(
    deps=[dashboard_encoding_gate],
    group_name="post_dbt_qa",
    description="Checks that panel content (tables, text, stats) fits within its gridPos bounding box.",
)
def dashboard_panel_fit_gate(context) -> Output[dict]:
    warn_only = _warn_only_enabled()
    result = _run_script("check_dashboard_panel_fit.py", ["--json"])
    metadata = _metadata_from_result(result)
    metadata["warn_only"] = warn_only

    if result.returncode == 2:
        raise Failure("dashboard_panel_fit_gate runtime failure", metadata=metadata)
    if result.returncode != 0 and not warn_only:
        raise Failure("dashboard_panel_fit_gate failed", metadata=metadata)
    if result.returncode != 0 and warn_only:
        context.log.warning(
            "dashboard_panel_fit_gate violations found but continuing due to DASHBOARD_POLICY_GATE_WARN_ONLY=true"
        )

    return Output({"exit_code": result.returncode, "warn_only": warn_only}, metadata=metadata)


@asset(
    deps=[dashboard_panel_fit_gate],
    group_name="post_dbt_qa",
    description=(
        "Playwright visual check: renders each Grafana dashboard in a headless "
        "browser and detects text panels where rendered markdown overflows the "
        "visible panel area.  Ground-truth complement to the static panel-fit gate."
    ),
)
def dashboard_visual_overflow_gate(context) -> Output[dict]:
    warn_only = _warn_only_enabled()
    result = _run_script("check_dashboard_text_overflow.py", ["--json"])
    metadata = _metadata_from_result(result)
    metadata["warn_only"] = warn_only

    if result.returncode == 2:
        raise Failure("dashboard_visual_overflow_gate runtime failure", metadata=metadata)
    if result.returncode != 0 and not warn_only:
        raise Failure("dashboard_visual_overflow_gate failed", metadata=metadata)
    if result.returncode != 0 and warn_only:
        context.log.warning(
            "dashboard_visual_overflow_gate violations found but continuing "
            "due to DASHBOARD_POLICY_GATE_WARN_ONLY=true"
        )

    return Output({"exit_code": result.returncode, "warn_only": warn_only}, metadata=metadata)


@asset(
    deps=[dashboard_json_lint_gate],
    group_name="post_dbt_qa",
    description="Enforces dashboard time-control policy for task 110.",
)
def dashboard_time_control_policy_gate(
    context,
) -> Output[dict]:
    warn_only = _warn_only_enabled()
    result = _run_script("check_dashboard_time_control_policy.py", ["--json"])
    metadata = _metadata_from_result(result)
    metadata["warn_only"] = warn_only

    if result.returncode == 2:
        raise Failure("dashboard_time_control_policy_gate runtime failure", metadata=metadata)
    if result.returncode != 0 and not warn_only:
        raise Failure("dashboard_time_control_policy_gate failed", metadata=metadata)
    if result.returncode != 0 and warn_only:
        context.log.warning(
            "dashboard_time_control_policy_gate violations found but continuing due to DASHBOARD_POLICY_GATE_WARN_ONLY=true"
        )

    return Output({"exit_code": result.returncode, "warn_only": warn_only}, metadata=metadata)


@asset(
    deps=[post_dbt_reporting_ready],
    group_name="post_dbt_qa",
    tags={"dagster/kind/postgres": "", "dagster/kind/python": ""},
    description=(
        "Validates that reporting tables contain meaningful (non-zero, non-null) "
        "data for every Grafana dashboard panel. Catches $0 income, missing "
        "liabilities, blank charts, and other 'looks empty' problems that the "
        "existing panel-has-rows check cannot detect."
    ),
)
def reporting_data_quality_gate(context) -> Output[dict]:
    warn_only = _warn_only_enabled()
    result = _run_script("check_reporting_data_quality.py", ["--json"])
    metadata = _metadata_from_result(result)
    metadata["warn_only"] = warn_only

    # Parse the JSON output for richer Dagster metadata
    try:
        parsed = json.loads(result.stdout) if result.stdout.strip() else {}
    except json.JSONDecodeError:
        parsed = {}

    if parsed:
        failed_checks = [c for c in parsed.get("checks", []) if not c["passed"]]
        if failed_checks:
            rows = "\n".join(
                f"| {c['check_id']} | {c.get('dashboard', '')} | {c['name']} | {c.get('severity', 'high')} | {c['detail'][:60]} |"
                for c in failed_checks
            )
            metadata["failing_checks"] = MetadataValue.md(
                f"| ID | Dashboard | Check | Severity | Detail |\n|---|---|---|---|---|\n{rows}"
            )
        metadata["total_checks"] = parsed.get("total", 0)
        metadata["passed_checks"] = parsed.get("passed", 0)
        metadata["failed_checks"] = parsed.get("failed", 0)

        # Surface per-dashboard summary so operators can see which dashboards are affected
        by_dashboard = parsed.get("by_dashboard", {})
        if by_dashboard:
            failing_dashboards = [
                dash for dash, summary in by_dashboard.items()
                if summary.get("status") == "FAIL"
            ]
            if failing_dashboards:
                dash_rows = "\n".join(
                    f"| {dash} | {by_dashboard[dash]['failed']}/{by_dashboard[dash]['total']} |"
                    for dash in failing_dashboards
                )
                metadata["failing_dashboards"] = MetadataValue.md(
                    f"| Dashboard | Failed/Total |\n|---|---|\n{dash_rows}"
                )
            metadata["dashboards_checked"] = len(by_dashboard)

    if result.returncode == 2:
        raise Failure("reporting_data_quality_gate runtime failure", metadata=metadata)
    if result.returncode != 0 and not warn_only:
        raise Failure(
            f"reporting_data_quality_gate: {parsed.get('failed', '?')} of "
            f"{parsed.get('total', '?')} data quality checks failed",
            metadata=metadata,
        )
    if result.returncode != 0 and warn_only:
        context.log.warning(
            "reporting_data_quality_gate failures found but continuing "
            "due to DASHBOARD_POLICY_GATE_WARN_ONLY=true"
        )

    return Output(
        {"exit_code": result.returncode, "warn_only": warn_only, "summary": parsed},
        metadata=metadata,
    )
