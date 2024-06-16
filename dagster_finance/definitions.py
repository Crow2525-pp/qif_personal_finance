import os

from dagster import Definitions, EnvVar
from dagster_dbt import DbtCliResource

from dagster_finance.resources import dbConnection
from dagster_duckdb_pandas import duckdb_pandas_io_manager
from dagster_duckdb import DuckDBResource

from .assets import finance_dbt_assets, upload_dataframe_to_database
from .constants import DBT_PROJECT_DIR

resources = {
    "local": {
        "personal_finance_database": dbConnection(
            connection_string="duckdb:///duckdb/finance.duckdb"
        ),
        # DuckDBResource(database="duckdb/finance.duckdb", schema="finance.raw"),
        "dbt": DbtCliResource(project_dir=os.fspath(DBT_PROJECT_DIR)),
    },
    "production": {
        "personal_finance_database": dbConnection(
            connection_string=EnvVar("POSTGRES_CONN_STR")
        ),
        "dbt": DbtCliResource(project_dir=os.fspath(DBT_PROJECT_DIR)),
    },
}

deployment_name = os.getenv("DAGSTER_DEPLOYMENT", "local")

defs = Definitions(
    assets=[finance_dbt_assets, upload_dataframe_to_database],
    resources=resources[deployment_name],
)
