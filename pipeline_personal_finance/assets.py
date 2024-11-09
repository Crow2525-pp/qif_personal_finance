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
    context,
    op,
    graph_asset,
    asset,
    multi_asset,
)
from dagster_dbt import DbtCliResource, dbt_assets
from sqlalchemy import text
from sqlalchemy.dialects.postgresql import JSONB
from typing import List
from .constants import dbt_manifest_path, QIF_FILES
from .resources import SqlAlchemyClientResource

# TODO Sort out this multiple asset bullshit
# TODO: Incremental Refresh
# TODO: Unique Indentifiers -
#   Group transactions by month.
# Assign a unique identifier to each transaction based on its description, amount, date, and its index within the group.
# TODO: Add Monitoring of new QIF Files within dir.


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

    def get_next_key(self, bank_name):
        if bank_name not in self.counters:
            raise ValueError(f"Bank name {bank_name} is not recognized.")
        next_key = self.counters[bank_name] + 1
        self.counters[bank_name] = next_key
        return next_key


# Create an instance of the generator
key_generator = PrimaryKeyGenerator()


def convert_qif_to_df(
    qif_file: Path, key_generator: PrimaryKeyGenerator, bank_name: str
) -> pd.DataFrame:
    qif_processor = quiffen.Qif.parse(str(qif_file), day_first=True)
    df = qif_processor.to_dataframe()

    if df is not None:
        df.dropna(how="all", axis=1, inplace=True)

        # Generate primary keys
        df["primary_key"] = [
            key_generator.get_next_key(bank_name) for _ in range(len(df))
        ]

        # add an ingestion timestamp
        df["ingestion_date"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    else:
        raise ValueError(f"Dataframe is empty for {qif_file}")

    return df


def fetch_qif_files(directory: Path) -> List:
    if directory.exists():
        return list(directory.glob("*.qif"))
    return []


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
    # TODO: How do you make this asset configurable by dagstger

    # Adding initial log message to confirm function start
    context.log.info("Starting the upload_dataframe_to_database asset.")

    # get a list of QIF Files and add them to a list.
    # Should this be relative to the Asset.py file or the Dagster core/daemon
    # previously worked with Dagstercore daemon location
    cwd = Path.cwd()
    cwd = cwd / "pipeline_personal_finance"
    # List directories within the current directory
    directories = [dir for dir in cwd.iterdir() if dir.is_dir()]

    # Print each directory
    for directory in directories:
        context.log.info(f"current working directory folders: {directory}")
    qif_filepath = Path(QIF_FILES)

    if qif_filepath.exists():
        context.log.debug("QIF file directory found.")
        # Find all QIF files in the directory
        # Ensure the landing schema exists
    schema = "landing"
    create_schema_sql = f"CREATE SCHEMA IF NOT EXISTS {schema};"
    verify_schema_sql = f"SELECT schema_name FROM information_schema.schemata WHERE schema_name = '{schema}';"
    check_db_sql = "SELECT current_database();"

    with personal_finance_database.get_connection() as conn:
        try:
            # Check the current database name
            context.log.info(f"Executing: {check_db_sql}")
            result = conn.execute(text(check_db_sql)).fetchone()
            current_db = result[0] if result else "Unknown"
            context.log.info(f"Connected to database: {current_db}")

            context.log.info(f"Creating schema with: {create_schema_sql}")
            conn.execute(text(create_schema_sql))
            conn.commit()  # Commit the schema creation
            context.log.info("Schema creation statement executed.")

            result = conn.execute(text(verify_schema_sql)).fetchone()
            if not result:
                raise RuntimeError(
                    f"Failed to create or verify the existence of schema '{schema}'."
                )
            context.log.info(f"Schema '{schema}' exists.")
        except Exception as e:
            context.log.error(f"Error ensuring schema exists: {e}")
            raise

    for file in qif_files:
        table_name = file.stem
        bank_name = table_name.split("_")[0]

        df = convert_qif_to_df(
            qif_file=file, key_generator=key_generator, bank_name=bank_name
        )

        dtype = {
            "category": JSONB(),
            "splits": JSONB(),
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
