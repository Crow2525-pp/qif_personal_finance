import os

from dagster import Definitions
from dagster_dbt import DbtCliResource

from dagster_finance.resources import postgres_db_resource

from .assets import (
    QIF_to_DF,
    finance_dbt_assets,
    ingest_dataframe_to_duckdb,
    upload_dataframe_to_postgres,
)
from .constants import DBT_PROJECT_DIR

from dagster_duckdb_pandas import duckdb_pandas_io_manager
from config import DUCKDB_FILEPATH

defs = Definitions(
    assets=[
        QIF_to_DF,
        finance_dbt_assets,
        upload_dataframe_to_postgres,
    ],  # ingest_dataframe_to_duckdb,
    resources={
        "postgres_db": postgres_db_resource,
        "dbt": DbtCliResource(project_dir=os.fspath(DBT_PROJECT_DIR)),
        # "io_manager": duckdb_pandas_io_manager.configured(
        # {"database": DUCKDB_FILEPATH}
        # ),
    },
)
