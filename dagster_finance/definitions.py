import os

from dagster import Definitions, EnvVar
from dagster_dbt import DbtCliResource

from dagster_finance.resources import pgConnection
from dagster_duckdb_pandas import duckdb_pandas_io_manager

from .assets import (
    QIF_to_DF,
    finance_dbt_assets,
    ingest_dataframe_to_duckdb,
    upload_dataframe_to_postgres,
)
from .constants import DBT_PROJECT_DIR


defs = Definitions(
    assets=[
        QIF_to_DF,
        finance_dbt_assets,
        upload_dataframe_to_postgres,
    ],  # ingest_dataframe_to_duckdb,
    resources={
        "postgres_db": pgConnection(EnvVar("POSTGRES_CONN_STR")),
        "dbt": DbtCliResource(project_dir=os.fspath(DBT_PROJECT_DIR)),
        "io_manager": duckdb_pandas_io_manager(database="duckdb/finance.duckdb", schema="finance"),
        }
    )