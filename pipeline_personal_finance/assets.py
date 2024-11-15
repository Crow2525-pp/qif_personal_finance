from datetime import datetime
import os
from pathlib import Path

import pandas as pd
import quiffen
from dagster import (
    AssetExecutionContext,
    AssetOut,
    MetadataValue,
    Output,
    multi_asset,
)
from dagster_dbt import DbtCliResource, dbt_assets
from sqlalchemy import text
from typing import List
from .constants import dbt_manifest_path, QIF_FILES
from .resources import SqlAlchemyClientResource

# TODO: Incremental Refresh
# TODO: Unique Indentifiers -
#   Group transactions by month.
# Assign a unique identifier to each transaction based on its description, amount, date, and its index within the group.
# TODO: Add Monitoring of new QIF Files within dir.


# TODO: Move dbt_assets to a seperate file?
@dbt_assets(
    manifest=dbt_manifest_path,
)
def finance_dbt_assets(context: AssetExecutionContext, dbt: DbtCliResource):
    # TODO: find out why dagster_deployment env var is not working. Fixed as Prod for moment.
    deployment_name = os.getenv("DAGSTER_DEPLOYMENT", "prod")
    target = "prod" if deployment_name == "prod" else "dev"
    yield from dbt.cli(["build", "--target", target], context=context).stream()


class PrimaryKeyGenerator:
    def __init__(self):
        self.counters = {"ING": 20000, "Bendigo": 40000, "Adelaide": 60000}

    # BUG: Where a bank has multiple accounts you'd expect the number to increment
    # over the two banks.  Probably not needed.
    def get_next_key(self, bank_name):
        if bank_name not in self.counters:
            raise ValueError(f"Bank name {bank_name} is not recognized.")
        next_key = self.counters[bank_name] + 1
        self.counters[bank_name] = next_key
        return next_key


# Create an instance of the generator
key_generator = PrimaryKeyGenerator()


def process_qif_file(
    qif_file: Path, key_generator: PrimaryKeyGenerator, bank_name: str
) -> pd.DataFrame:
    df = quiffen.Qif.parse(str(qif_file), day_first=True).to_dataframe()

    df.dropna(how="all", axis=1, inplace=True)

    df["primary_key"] = [key_generator.get_next_key(bank_name) for _ in range(len(df))]

    # TODO: Consider UTC time
    df["ingestion_date"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    return df


def fetch_qif_files(directory: Path) -> List:
    if directory.exists():
        return list(directory.glob("*.qif"))
    return []


def verify_database_schema(
    context: AssetExecutionContext,
    personal_finance_database: SqlAlchemyClientResource,
    schema: str = "landing",
):
    verify_schema_sql = f"SELECT schema_name FROM information_schema.schemata WHERE schema_name = '{schema}';"
    create_schema_sql = f"CREATE SCHEMA IF NOT EXISTS {schema};"
    check_db_sql = "SELECT current_database();"

    with personal_finance_database.get_connection() as conn:
        try:
            # Check if Schema is in DB Information Schema
            context.log.debug(f"Executing: {check_db_sql}")
            result = conn.execute(text(check_db_sql)).fetchone()
            current_db = result[0] if result else "Unknown"
            context.log.debug(f"Connected to database: {current_db}")
            if result:
                context.log.info(
                    f"Schema '{schema}' already exists. Skipping creation."
                )
                return

            # If not, then try and create it
            context.log.info(f"Create if not exists schema with: {create_schema_sql}")
            conn.execute(text(create_schema_sql))
            conn.commit()
            context.log.debug("Schema creation committed.")

            # Check the information_schema to ensure it's there.
            context.log.debug(f"Verifying schema with: {verify_schema_sql}")
            result = conn.execute(text(verify_schema_sql)).fetchone()
            if not result:
                raise RuntimeError(
                    f"Schema '{schema}' was not found in the database after creation."
                )
            context.log.info(f"Schema '{schema}' exists and verified.")
        except Exception as e:
            context.log.error(f"Error ensuring schema exists: {e}")
            raise


# QUERY: I am not sure why I think I need to break multi into parts?
# It doesn't make a lot of sense to me.  Having the assets feed into DBT is fine.
# Perhaps I read something somewhere that has me concerned.
@multi_asset(
    outs={
        "Adelaide_Homeloan_Transactions": AssetOut(is_required=False),
        "Adelaide_Offset_Transactions": AssetOut(is_required=False),
        "Bendigo_Homeloan_Transactions": AssetOut(is_required=False),
        "Bendigo_Offset_Transactions": AssetOut(is_required=False),
        "ING_BillsBillsBills_Transactions": AssetOut(is_required=False),
        "ING_Countdown_Transactions": AssetOut(is_required=False),
    },
    can_subset=True,
    group_name="qif_ingestion",
)
def upload_dataframe_to_database(
    context: AssetExecutionContext, personal_finance_database: SqlAlchemyClientResource
):

    # get a list of QIF Files and add them to a list.
    # Should this be relative to the Asset.py file or the Dagster core/daemon
    # previously worked with Dagstercore daemon location
    cwd = Path.cwd()
    cwd = cwd / "pipeline_personal_finance"
    # List directories within the current directory
    directories = [dir for dir in cwd.iterdir() if dir.is_dir()]

    # Print each directory
    for directory in directories:
        context.log.debug(f"current working directory folders: {directory}")

    schema = "landing"
    verify_database_schema(context, personal_finance_database, schema)

    qif_filepath = Path(QIF_FILES)
    if qif_filepath.exists():
        context.log.debug("QIF file directory found.")

    qif_files = fetch_qif_files(qif_filepath)

    for file in qif_files:
        table_name = file.stem
        bank_name = table_name.split("_")[0]

        df = process_qif_file(
            qif_file=file, key_generator=key_generator, bank_name=bank_name
        )

        dtype = {
            "category": "json",
            "splits": "json",
        }

        # Upload the dataframe
        if df is not None:
            try:
                df.to_sql(
                    name=table_name,
                    con=personal_finance_database.get_connection(),
                    schema=schema,
                    if_exists="replace",
                    index=False,
                    dtype=dtype,
                )

                context.add_output_metadata(
                    metadata={
                        "data_types": MetadataValue.md(df.dtypes.to_markdown()),
                        "num_records": len(df),
                        "preview": MetadataValue.md(df.head().to_markdown()),
                    },
                    output_name=table_name,
                )
                context.log.info(
                    f"Data uploaded successfully to {schema}.{table_name} table."
                )

                yield Output(value=table_name, output_name=table_name)
            except Exception as e:
                context.log.error(f"Error uploading data to {schema}.{table_name}: {e}")
                raise
        else:
            context.log.error(f"No data to upload for {table_name}.")
