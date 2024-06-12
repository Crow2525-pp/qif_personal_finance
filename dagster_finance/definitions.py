import json
import os

from dagster import Definitions, EnvVar
from dagster_dbt import DbtCliResource

from dagster_finance.resources import pgConnection
from dagster_duckdb_pandas import duckdb_pandas_io_manager

from .assets import (
    finance_dbt_assets,
    ING_BillsBillsBills_Transactions,
    ING_Countdown_Transactions,
    Bendigo_Bank_Offset_Transactions,
    Bendigo_Bank_Homeloan_Transactions,
    Adelaide_Offset_Transactions,
    Adelaide_Homeloan_Transactions,
)
from .constants import DBT_PROJECT_DIR

defs = Definitions(
    assets=[
        ING_BillsBillsBills_Transactions,
        ING_Countdown_Transactions,
        Bendigo_Bank_Offset_Transactions,
        Bendigo_Bank_Homeloan_Transactions,
        Adelaide_Offset_Transactions,
        Adelaide_Homeloan_Transactions,
        finance_dbt_assets,
    ],  # ingest_dataframe_to_duckdb,
    resources={
        "postgres_db": pgConnection(connection_url=EnvVar("POSTGRES_CONN_STR")),
        "dbt": DbtCliResource(project_dir=os.fspath(DBT_PROJECT_DIR)),
        "io_manager": duckdb_pandas_io_manager.configured({"database":"duckdb/finance.duckdb", "schema":"finance.raw"}),
        }
    )