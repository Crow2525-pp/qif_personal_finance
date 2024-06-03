import os

from dagster import Definitions, EnvVar
from dagster_dbt import DbtCliResource

from dagster_finance.resources import pgConnection
from dagster_duckdb_pandas import duckdb_pandas_io_manager

from .assets import (
    finance_dbt_assets,
    upload_ing_countdown,
    upload_ing_billsbillsbills,
    upload_bendigo_bank_offset,
    upload_bendigo_bank_homeloan,
    upload_adelaide_offset,
    upload_adelaide_homeloan,
)
from .constants import DBT_PROJECT_DIR


defs = Definitions(
    assets=[
        upload_ing_countdown,
        upload_ing_billsbillsbills,
        upload_bendigo_bank_offset,
        upload_bendigo_bank_homeloan,
        upload_adelaide_offset,
        upload_adelaide_homeloan,
        finance_dbt_assets,
    ],  # ingest_dataframe_to_duckdb,
    resources={
        #"postgres_db": pgConnection(EnvVar("POSTGRES_CONN_STR")),
        "dbt": DbtCliResource(project_dir=os.fspath(DBT_PROJECT_DIR)),
        "io_manager": duckdb_pandas_io_manager.configured({"database":"duckdb/finance.duckdb", "schema":"finance.raw"}),
        }
    )