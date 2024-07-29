import os

from dagster import Definitions, EnvVar
from dagster_dbt import DbtCliResource
from dotenv import load_dotenv

from pipeline_personal_finance.resources import SqlAlchemyClientResource
from dagster_duckdb_pandas import duckdb_pandas_io_manager
from dagster_duckdb import DuckDBResource

from .assets import finance_dbt_assets, upload_dataframe_to_database
from .constants import DBT_PROJECT_DIR
from .resources import SqlAlchemyClientResource

load_dotenv()

resources = {
     "env": {
        "personal_finance_database": SqlAlchemyClientResource(
            drivername="postgresql+psycopg2",
            username=EnvVar("DAGSTER_POSTGRES_USER"),
            password=EnvVar("DAGSTER_POSTGRES_PASSWORD"),
            host=EnvVar("DAGSTER_POSTGRES_HOST"),
            port=int(os.getenv("DAGSTER_POSTGRES_PORT")),
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
            port=int(os.getenv("DAGSTER_POSTGRES_PORT")),
            database=EnvVar("DAGSTER_POSTGRES_DB"),
            ),
        "dbt": DbtCliResource(project_dir=os.fspath(DBT_PROJECT_DIR)),
    },
}

deployment_name = os.getenv("DAGSTER_DEPLOYMENT", "dev")

defs = Definitions(
    assets=[finance_dbt_assets, upload_dataframe_to_database],
    resources=resources[deployment_name],
)
