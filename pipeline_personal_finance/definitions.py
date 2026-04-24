import hashlib
import os

from dagster import Definitions, EnvVar, define_asset_job, sensor, RunRequest, SkipReason
from dotenv import load_dotenv

from .resources import SqlAlchemyClientResource
from .assets import finance_dbt_assets, upload_dataframe_to_database
from .dashboard_policy_gate import (
    post_dbt_reporting_ready,
    dashboard_json_lint_gate,
    dashboard_encoding_gate,
    dashboard_panel_fit_gate,
    dashboard_visual_overflow_gate,
    dashboard_time_control_policy_gate,
    reporting_data_quality_gate,
)
from .assets_dashboard_qa import dashboard_quality_gate
from .postgres_readiness_gate import postgres_role_readiness_gate
from .constants import QIF_FILES, build_dbt_resource
from .run_timeout import find_stale_runs, parse_timeout_hours

load_dotenv()


def _qif_run_key(qif_directory: str, qif_files: list[str]) -> str:
    digest = hashlib.sha256()
    for filename in sorted(qif_files):
        path = os.path.join(qif_directory, filename)
        digest.update(filename.encode())
        with open(path, "rb") as file_obj:
            for chunk in iter(lambda: file_obj.read(1024 * 1024), b""):
                digest.update(chunk)
    return f"qif_files_{digest.hexdigest()}"

qif_pipeline_job = define_asset_job(
    name="qif_pipeline_job",
    selection=[
        postgres_role_readiness_gate,
        upload_dataframe_to_database,
        finance_dbt_assets,
        post_dbt_reporting_ready,
        reporting_data_quality_gate,
        dashboard_json_lint_gate,
        dashboard_encoding_gate,
        dashboard_panel_fit_gate,
        dashboard_visual_overflow_gate,
        dashboard_time_control_policy_gate,
        dashboard_quality_gate,
    ],
    description="Complete QIF processing pipeline - ingestion, dbt transformations, and dashboard QA gates",
)

resources = {
    "dev": {
        "personal_finance_database": SqlAlchemyClientResource(
            drivername="postgresql+psycopg2",
            username=EnvVar("DAGSTER_POSTGRES_USER"),
            password=EnvVar("DAGSTER_POSTGRES_PASSWORD"),
            host=EnvVar("DAGSTER_POSTGRES_HOST"),
            port=int(os.getenv("DAGSTER_POSTGRES_PORT", "5432")),
            database=EnvVar("DAGSTER_POSTGRES_DB"),
        ),
        "dbt": build_dbt_resource(),
    },
    "prod": {
        "personal_finance_database": SqlAlchemyClientResource(
            drivername="postgresql+psycopg2",
            username=EnvVar("DAGSTER_POSTGRES_USER"),
            password=EnvVar("DAGSTER_POSTGRES_PASSWORD"),
            host=EnvVar("DAGSTER_POSTGRES_HOST"),
            port=int(os.getenv("DAGSTER_POSTGRES_PORT", "5432")),
            database=EnvVar("DAGSTER_POSTGRES_DB"),
        ),
        "dbt": build_dbt_resource(),
    },
}

@sensor(job=qif_pipeline_job)
def qif_file_sensor(context):
    """
    Sensor that monitors the QIF files directory for new .qif files
    and triggers the pipeline when changes are detected.
    """
    qif_directory = QIF_FILES
    
    if not os.path.exists(qif_directory):
        context.log.warning(f"QIF directory does not exist: {qif_directory}")
        return SkipReason(f"QIF directory does not exist: {qif_directory}")
    
    qif_files = [f for f in os.listdir(qif_directory) if f.endswith('.qif')]
    
    if not qif_files:
        return SkipReason("No QIF files found in directory")
    
    # Include file contents so replacing an existing QIF file triggers a new run.
    run_key = _qif_run_key(qif_directory, qif_files)
    
    context.log.info(f"Found {len(qif_files)} QIF files: {qif_files}")
    
    yield RunRequest(
        run_key=run_key,
        tags={
            "qif_file_count": str(len(qif_files)),
            "qif_files": ",".join(qif_files)
        }
    )


def _terminate_run(instance, run_id: str) -> None:
    if hasattr(instance, "terminate_run"):
        instance.terminate_run(run_id)
        return
    run_launcher = getattr(instance, "run_launcher", None)
    if run_launcher is not None and hasattr(run_launcher, "terminate"):
        run_launcher.terminate(run_id)
        return
    raise RuntimeError("Dagster instance does not expose a run termination API")


@sensor(job=qif_pipeline_job, minimum_interval_seconds=300)
def stuck_run_timeout_sensor(context):
    """
    Detect long-running qif_pipeline_job runs and request termination.
    """
    timeout_hours = parse_timeout_hours(os.getenv("QIF_DAGSTER_RUN_TIMEOUT_HOURS", "2"))
    runs_getter = getattr(context.instance, "get_runs", None)
    if runs_getter is None:
        return SkipReason("Dagster instance does not expose get_runs")

    stale_runs = find_stale_runs(
        runs_getter(),
        job_name=qif_pipeline_job.name,
        timeout_hours=timeout_hours,
    )

    if not stale_runs:
        return SkipReason(f"No qif_pipeline_job runs exceeded {timeout_hours:g} hours")

    terminated_runs: list[str] = []
    for run_id, started_at in stale_runs:
        try:
            _terminate_run(context.instance, run_id)
            terminated_runs.append(run_id)
            context.log.warning(
                f"Requested termination for stale run {run_id} started at {started_at.isoformat()}"
            )
        except Exception as exc:
            context.log.warning(
                f"Failed to terminate stale run {run_id}: {exc}"
            )

    if terminated_runs:
        run_list = ", ".join(terminated_runs)
        return SkipReason(
            f"Requested termination for {len(terminated_runs)} stale run(s) older than {timeout_hours:g} hours: {run_list}"
        )

    return SkipReason(
        f"Identified {len(stale_runs)} stale run(s) older than {timeout_hours:g} hours but termination failed"
    )

deployment_name = os.getenv("DAGSTER_DEPLOYMENT", "prod")
if deployment_name not in resources:
    valid_deployments = ", ".join(sorted(resources))
    raise ValueError(
        f"Unsupported DAGSTER_DEPLOYMENT={deployment_name!r}. "
        f"Expected one of: {valid_deployments}."
    )

defs = Definitions(
    assets=[
        postgres_role_readiness_gate,
        finance_dbt_assets,
        upload_dataframe_to_database,
        post_dbt_reporting_ready,
        reporting_data_quality_gate,
        dashboard_json_lint_gate,
        dashboard_encoding_gate,
        dashboard_panel_fit_gate,
        dashboard_visual_overflow_gate,
        dashboard_time_control_policy_gate,
        dashboard_quality_gate,
    ],
    resources=resources[deployment_name],
    jobs=[qif_pipeline_job],
    sensors=[qif_file_sensor, stuck_run_timeout_sensor],
)
