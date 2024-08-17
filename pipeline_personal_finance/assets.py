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
    get_dagster_logger,
    logger,
    multi_asset,
)
from dagster_dbt import DbtCliResource, dbt_assets
from sqlalchemy import text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.types import JSON

logger = get_dagster_logger()

from .constants import dbt_manifest_path
from .resources import SqlAlchemyClientResource


@dbt_assets(
    manifest=dbt_manifest_path,
)
def finance_dbt_assets(context: AssetExecutionContext, dbt: DbtCliResource):
    # TODO: find out why dagster_deployment env var is not working. Fixed as Prod for moment.
    deployment_name = os.getenv("DAGSTER_DEPLOYMENT", "prod")
    target = "prod" if deployment_name == "prod" else "dev"
    yield from dbt.cli(["build", f"--target", target], context=context).stream()


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
    qif_processor = quiffen.Qif.parse(str(qif_file), day_first=False)
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
        raise ValueError(f"Datafrmae is empty for {qif_file}")

    return df


@multi_asset(
    outs={
        "Adelaide_Homeloan_Transactions": AssetOut(is_required=False),
        "Adelaide_Offset_Transactions": AssetOut(is_required=False),
        "Bendigo_Bank_Homeloan_Transactions": AssetOut(is_required=False),
        "Bendigo_Bank_Offset_Transactions": AssetOut(is_required=False),
        "ING_BillsBillsBills_Transactions": AssetOut(is_required=False),
        "ING_Countdown_Transactions": AssetOut(is_required=False),
    },
    can_subset=True,
    group_name="qif_ingestion",
)
def upload_dataframe_to_database(
    context: AssetExecutionContext, personal_finance_database: SqlAlchemyClientResource):
    # TODO: How do you make this asset configurable by dagstger

    # Adding initial log message to confirm function start
    context.log.info("Starting the upload_dataframe_to_database asset.")

    # get a list of QIF Files and add them to a list.
    qif_filepath = Path("qif_files")
    
    if qif_filepath.exists():
        context.log.debug("QIF file directory found.")
        # Find all QIF files in the directory
        qif_files = list(qif_filepath.glob("*.qif"))
    
        if qif_files:
            context.log.info(f"Found {len(qif_files)} QIF files.")
            # Get the first few elements of the list
            qif_files_head = qif_files[:5]
            
            # Convert the list of Path objects to a list of strings
            qif_files_head_str = [str(qif_file) for qif_file in qif_files_head]
            
            # Create a markdown representation of the list
            markdown_list = "\n".join(f"- {qif_file}" for qif_file in qif_files_head_str)
            
            # Log the markdown list using context.log.debug
            context.log.debug(f"First few QIF files:\n{markdown_list}")     
        else:
            context.log.critical("No QIF files found.")
    else:
        context.log.critical(f"Directory '{qif_filepath}' does not exist.")

    # Ensure the raw schema exists
    schema = "raw"
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
