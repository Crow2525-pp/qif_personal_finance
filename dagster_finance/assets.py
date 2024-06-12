import hashlib
from datetime import datetime
from pathlib import Path
from typing import Dict, Optional

import pandas as pd
import quiffen
from dagster import (AssetExecutionContext, MetadataValue, asset,
                     get_dagster_logger, logger)
from dagster_dbt import DbtCliResource, dbt_assets
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
            raise ValueError("Bank name is not recognized.")
        self.counters[bank_name] += 1
        return self.counters[bank_name]

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
    else:
        raise ValueError(f"Datafrmae is empty for {qif_file}")

    return df


@asset(compute_kind="python", group_name="qif_ingestion")
def Adelaide_Homeloan_Transactions():#context: AssetExecutionContext):
    df = convert_qif_to_df(qif_file=Path('qif_files/Adelaide_Homeloan_Transactions.qif'), key_generator=key_generator, bank_name="Adelaide")
    # context.add_output_metadata(
    # metadata={
    #     "num_records": len(df),  # Metadata can be any key-value pair
    #     "preview": MetadataValue.md(df.head().to_markdown()),
    #     # The `MetadataValue` class has useful static methods to build Metadata
    #     }
    # )   
    return df

if __name__ == '__main__':
    df = Adelaide_Homeloan_Transactions()
    print(df.head())
    
        
@asset(compute_kind="python", group_name="qif_ingestion")
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

@asset(compute_kind="python", group_name="qif_ingestion")
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

@asset(compute_kind="python", group_name="qif_ingestion")
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

@asset(compute_kind="python", group_name="qif_ingestion")
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

@asset(compute_kind="python", group_name="qif_ingestion")
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


def upload_dataframe_to_postgres(
    context, QIF_to_DF: Dict[str, Optional[pd.DataFrame]], my_conn: pgConnection
) -> None:

    schema = "landing"

    # Upload the dataframe
    for table_name, df in QIF_to_DF.items():
        if df is not None:
            dtype = {
                "category": JSONB,  # Ensuring SQLAlchemy treats this column as JSONB
                "splits": JSONB,
            }
            df.to_sql(
                name=table_name,
                con=my_conn,
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
            logger.info(f"Data uploaded successfully to {schema}.{table_name} table.")
        else:
            logger.error(f"No data to upload for {table_name}.")
