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
    group_name="policy_gates",
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
    group_name="policy_gates",
    description="Enforces dashboard time-control policy for task 110.",
)
def dashboard_time_control_policy_gate(
    context,
) -> Output[dict]:
    warn_only = _warn_only_enabled()
    result = _run_script("check_dashboard_time_control_policy.py", ["--json", "--strict"])
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
