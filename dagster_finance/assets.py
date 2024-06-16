import hashlib
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional

import pandas as pd
import quiffen
from dagster import (AssetExecutionContext, MetadataValue, asset,
                     get_dagster_logger, logger)
from dagster_dbt import DbtCliResource, dbt_assets
from sqlalchemy import text
from sqlalchemy.dialects.postgresql import JSONB

logger = get_dagster_logger()

from .constants import dbt_manifest_path
from .resources import pgConnection


@dbt_assets(
    manifest=dbt_manifest_path,
)
def finance_dbt_assets(context: AssetExecutionContext, dbt: DbtCliResource):
    yield from dbt.cli(["build"], context=context).stream()


class PrimaryKeyGenerator:
    def __init__(self):
        self.counters = {
            'ING': 20000,
            'Bendigo': 40000,
            'Adelaide': 60000
        }

    def get_next_key(self, bank_name):
        if bank_name not in self.counters:
            raise ValueError(f"Bank name {bank_name} is not recognized.")
        next_key = self.counters[bank_name] + 1
        self.counters[bank_name] = next_key
        return next_key

# Create an instance of the generator
key_generator = PrimaryKeyGenerator()


def convert_qif_to_df(qif_file: Path, key_generator: PrimaryKeyGenerator, bank_name: str) -> pd.DataFrame:
    qif_processor = quiffen.Qif.parse(qif_file, day_first=False)
    df = qif_processor.to_dataframe()

    if df is not None:
        df.dropna(how="all", axis=1, inplace=True)

        # Generate primary keys
        df['primary_key'] = [key_generator.get_next_key(bank_name) for _ in range(len(df))]

        # add an ingestion timestamp
        df["ingestion_date"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        upload_dataframe_to_postgres(df=df, table_name=qif_file.stem)
    else:
        raise ValueError(f"Datafrmae is empty for {qif_file}")

    return df


@asset(compute_kind="duckdb", group_name="qif_ingestion_duckdb")
def Adelaide_Homeloan_Transactions(context: AssetExecutionContext):
    df = convert_qif_to_df(qif_file=Path('qif_files/Adelaide_Homeloan_Transactions.qif'), key_generator=key_generator, bank_name="Adelaide")
    context.add_output_metadata(
    metadata={
        "num_records": len(df),  # Metadata can be any key-value pair
        "preview": MetadataValue.md(df.head().to_markdown()),
        # The `MetadataValue` class has useful static methods to build Metadata
        }
    )   
    return df

@asset(compute_kind="duckdb", group_name="qif_ingestion_duckdb")
def Adelaide_Offset_Transactions(context: AssetExecutionContext):
    df = convert_qif_to_df(qif_file=Path('qif_files/Adelaide_Offset_Transactions.qif'), key_generator=key_generator, bank_name="Adelaide")
    context.add_output_metadata(
    metadata={
        "num_records": len(df),  # Metadata can be any key-value pair
        "preview": MetadataValue.md(df.head().to_markdown()),
        # The `MetadataValue` class has useful static methods to build Metadata
        }
    )   
    return df

@asset(compute_kind="duckdb", group_name="qif_ingestion_duckdb")
def Bendigo_Bank_Homeloan_Transactions(context: AssetExecutionContext):
    df = convert_qif_to_df(qif_file=Path('qif_files/Bendigo_Bank_Homeloan_Transactions.qif'), key_generator=key_generator, bank_name="Bendigo")
    context.add_output_metadata(
    metadata={
        "num_records": len(df),  # Metadata can be any key-value pair
        "preview": MetadataValue.md(df.head().to_markdown()),
        # The `MetadataValue` class has useful static methods to build Metadata
        }
    )   
    return df

@asset(compute_kind="duckdb", group_name="qif_ingestion_duckdb")
def Bendigo_Bank_Offset_Transactions(context: AssetExecutionContext):
    df = convert_qif_to_df(qif_file=Path('qif_files/Bendigo_Bank_Offset_Transactions.qif'), key_generator=key_generator, bank_name="Bendigo")
    context.add_output_metadata(
    metadata={
        "num_records": len(df),  # Metadata can be any key-value pair
        "preview": MetadataValue.md(df.head().to_markdown()),
        # The `MetadataValue` class has useful static methods to build Metadata
        }
    )   
    return df

@asset(compute_kind="duckdb", group_name="qif_ingestion_duckdb")
def ING_BillsBillsBills_Transactions(context: AssetExecutionContext):
    df = convert_qif_to_df(qif_file=Path('qif_files/ING_BillsBillsBills_Transactions.qif'), key_generator=key_generator, bank_name="ING")
    context.add_output_metadata(
    metadata={
        "num_records": len(df),  # Metadata can be any key-value pair
        "preview": MetadataValue.md(df.head().to_markdown()),
        # The `MetadataValue` class has useful static methods to build Metadata
        }
    )   
    return df

@asset(compute_kind="duckdb", group_name="qif_ingestion_duckdb")
def ING_Countdown_Transactions(context: AssetExecutionContext):
    df = convert_qif_to_df(qif_file=Path('qif_files/ING_Countdown_Transactions.qif'), key_generator=key_generator, bank_name="ING")
    context.add_output_metadata(
    metadata={
        "num_records": len(df),  # Metadata can be any key-value pair
        "preview": MetadataValue.md(df.head().to_markdown()),
        # The `MetadataValue` class has useful static methods to build Metadata
        }
    )   
    return df





@asset(compute_kind="postgres", group_name="qif_ingestion_pg")
def upload_dataframe_to_postgres(
    context: AssetExecutionContext, postgres_db: pgConnection
) -> None:
    schema = "raw"
    qif_filepath = Path('qif_files')
    qif_files = qif_filepath.glob("*.qif")

    # Ensure the raw schema exists
    create_schema_sql = f"CREATE SCHEMA IF NOT EXISTS {schema};"
    verify_schema_sql = f"SELECT schema_name FROM information_schema.schemata WHERE schema_name = '{schema}';"

    with postgres_db._db_connection.engine.connect() as conn:
        try:
            context.log.info(f"Creating schema with: {create_schema_sql}")
            conn.execute(text(create_schema_sql))
            context.log.info("Schema creation statement executed.")
            
            result = conn.execute(text(verify_schema_sql)).fetchone()
            if not result:
                raise RuntimeError(f"Failed to create or verify the existence of schema '{schema}'.")
            context.log.info(f"Schema '{schema}' exists.")
        except Exception as e:
            context.log.error(f"Error ensuring schema exists: {e}")
            raise

    for file in qif_files:
        qif_processor = quiffen.Qif.parse(file, day_first=False)
        df = qif_processor.to_dataframe()
        table_name = file.stem

        # Upload the dataframe
        if df is not None:
            dtype = {
                "category": JSONB(),  # Use instances of the types
                "splits": JSONB(),
            }
            try:
                df.to_sql(
                    name=table_name,
                    con=postgres_db._db_connection.engine,  # Use the engine from DBConnection
                    schema=schema,
                    if_exists="replace",
                    index=False,
                    dtype=dtype,
                )
                context.add_output_metadata(
                    metadata={
                        "num_records": len(df),  # Metadata can be any key-value pair
                        "preview": MetadataValue.md(df.head().to_markdown()),
                    }
                )
                context.log.info(f"Data uploaded successfully to {schema}.{table_name} table.")
            except Exception as e:
                context.log.error(f"Error uploading data to {schema}.{table_name}: {e}")
                raise
        else:
            context.log.error(f"No data to upload for {table_name}.")