from datetime import datetime
import json
from typing import Mapping, Optional, Dict
import pandas as pd
import quiffen
from pathlib import Path
import duckdb
import hashlib
from dagster import (
    Any,
    AssetKey,
    AssetOut,
    logger,
    asset,
    get_dagster_logger,
    MetadataValue,
    AssetExecutionContext,
    multi_asset,
)
from dagster_dbt import (
    DagsterDbtTranslator,
    DbtCliResource,
    dbt_assets,
    DagsterDbtTranslatorSettings,
)
from sqlalchemy import create_engine
from sqlalchemy.dialects.postgresql import JSONB
from .resources import pgConnection

logger = get_dagster_logger()

from .constants import dbt_manifest_path


# class CustomDagsterDbtTranslator(DagsterDbtTranslator):
#     def get_asset_key(self, dbt_resource_props: Mapping[str, Any]) -> AssetKey:
#         return super().get_asset_key(dbt_resource_props).with_prefix("qif_files")

dagster_dbt_translator = DagsterDbtTranslator(
    settings=DagsterDbtTranslatorSettings(enable_asset_checks=False)
)


@dbt_assets(
    manifest=dbt_manifest_path,
    dagster_dbt_translator=dagster_dbt_translator,
)
def finance_dbt_assets(context: AssetExecutionContext, dbt: DbtCliResource):
    yield from dbt.cli(["build"], context=context).stream()


def create_composite_key(row: Dict[str, str]) -> Optional[str]:
    try:
        date = row.get("date", "")
        amount = row.get("amount", "")
        description = row.get("payee", "") if "payee" in row else row.get("memo", "")

        if not date or not amount:
            print(f"Skipping row due to missing values: {row}")
            return None

        hashed_description = (
            hashlib.md5(description.encode()).hexdigest() if description else ""
        )
        composite_key = f"{date}_{amount}_{hashed_description}"
        return composite_key

    except Exception as e:
        print(f"An error occurred while creating composite key: {e}")
        return None


# TODO the input should be each file in the QIF and the output should be an individual DF.


@asset(compute_kind="python", io_manager_key="io_manager")
def upload_dataframe_to_duck_db(df: pd.DataFrame) -> pd.DataFrame:
    """Setup to capture individual df within the io manager"""
    return df


@multi_asset(compute_kind="python",
             outs={
                 "Adelaide_Homeloan_Transactions": AssetOut(),
                 "Adelaide_Offset_Transactions": AssetOut(),
                 "Bendigo_Bank_Homeloan_Transactions": AssetOut(),
                 "Bendigo_Bank_Offset_Transactions": AssetOut(),
                 "ING_BillsBillsBills_Transactions": AssetOut(),
                 "ING_Countdown_Transactions": AssetOut()
             })
def QIF_to_DF(context: AssetExecutionContext) -> Dict[str, pd.DataFrame]:
    """
    Converts Quicken Interchange Format (QIF) files in a folder to Pandas DataFrames.

    Parameters:
    - folder_path (str): The path to the folder containing QIF files.

    The account name (used for the SQL table name) will be the filename.

    Returns:
    - Dict[str, Optional[pd.DataFrame]]: A dictionary where keys are account names and values are DataFrames.
    """

    qif_folder_path = Path("qif_files")

    dictionary_of_dfs = {}
    list_of_source_qif_files = list(qif_folder_path.glob("*.qif"))

    for qif_file in list_of_source_qif_files:
        logger.debug(f"Processing qif file: {qif_file}")

        account_name = Path(qif_file).stem

        qif_processor = quiffen.Qif.parse(qif_file, day_first=False)

        df = qif_processor.to_dataframe()
        df.dropna(how="all", axis=1, inplace=True)

        # add a primary key
        df["composite_key"] = df.apply(lambda row: create_composite_key(row), axis=1)  # type: ignore

        # add an ingestion timestamp
        df["ingestion_date"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        upload_dataframe_to_duck_db(df)

        # collate df into a dict of dfs.
        dictionary_of_dfs[account_name] = df

        context.add_output_metadata(
            metadata={
                "num_records": len(df),  # Metadata can be any key-value pair
                "preview": MetadataValue.md(df.head().to_markdown()),
                # The `MetadataValue` class has useful static methods to build Metadata
            }
        )

    return dictionary_of_dfs


@multi_asset(compute_kind="python",
             outs={
                 "Adelaide_Homeloan_Transactions": AssetOut(),
                 "Adelaide_Offset_Transactions": AssetOut(),
                 "Bendigo_Bank_Homeloan_Transactions": AssetOut(),
                 "Bendigo_Bank_Offset_Transactions": AssetOut(),
                 "ING_BillsBillsBills_Transactions": AssetOut(),
                 "ING_Countdown_Transactions": AssetOut()
             },
             required_resource_keys={"pgConnection"})
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
