import os

from dagster import Definitions, EnvVar, define_asset_job, sensor, RunRequest, SkipReason
from dagster_dbt import DbtCliResource
from dotenv import load_dotenv

from .resources import SqlAlchemyClientResource
from .assets import finance_dbt_assets, upload_dataframe_to_database
from .assets_dashboard_qa import dashboard_quality_gate
from .constants import DBT_PROJECT_DIR, QIF_FILES

load_dotenv()

qif_pipeline_job = define_asset_job(
    name="qif_pipeline_job",
    selection=[upload_dataframe_to_database, finance_dbt_assets, dashboard_quality_gate],
    description="Complete QIF processing pipeline - ingestion, dbt transformations, and dashboard QA"
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
        "dbt": DbtCliResource(project_dir=os.fspath(DBT_PROJECT_DIR)),
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
        "dbt": DbtCliResource(project_dir=os.fspath(DBT_PROJECT_DIR)),
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
    
    # Create a run request with all current QIF files as the run key
    # This ensures the pipeline runs when new files are added
    run_key = f"qif_files_{'_'.join(sorted(qif_files))}"
    
    context.log.info(f"Found {len(qif_files)} QIF files: {qif_files}")
    
    yield RunRequest(
        run_key=run_key,
        tags={
            "qif_file_count": str(len(qif_files)),
            "qif_files": ",".join(qif_files)
        }
    )

deployment_name = os.getenv("DAGSTER_DEPLOYMENT", "prod")

defs = Definitions(
    assets=[finance_dbt_assets, upload_dataframe_to_database, dashboard_quality_gate],
    resources=resources[deployment_name],
    jobs=[qif_pipeline_job],
    sensors=[qif_file_sensor],
)

