from datetime import datetime
import json
from typing import Optional, Dict
import pandas as pd
import quiffen
from pathlib import Path
import duckdb
import hashlib
from dagster import (
    logger,
    asset,
    get_dagster_logger,
    MetadataValue,
    AssetExecutionContext,
)
from dagster_dbt import DbtCliResource, dbt_assets
from sqlalchemy import create_engine
from sqlalchemy.dialects.postgresql import JSONB

logger = get_dagster_logger()

from .constants import dbt_manifest_path

@dbt_assets(manifest=dbt_manifest_path)
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


@asset(compute_kind="python")
def QIF_to_DF(context: AssetExecutionContext) -> Dict[str, Optional[pd.DataFrame]]:
    """
    Converts Quicken Interchange Format (QIF) files in a folder to Pandas DataFrames.

    Parameters:
    - folder_path (str): The path to the folder containing QIF files.

    The account name (used for the SQL table name) will be the filename.

    Returns:
    - Dict[str, Optional[pd.DataFrame]]: A dictionary where keys are account names and values are DataFrames.
    """

    qif_folder_path = Path(QIF_FOLDERPATH)

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

        # collate df into a df of dfs because Dagster really only sees outputs as dfs.
        dictionary_of_dfs[account_name] = df

        context.add_output_metadata(
            metadata={
                "num_records": len(df),  # Metadata can be any key-value pair
                "preview": MetadataValue.md(df.head().to_markdown()),
                # The `MetadataValue` class has useful static methods to build Metadata
            }
        )

    return dictionary_of_dfs


# TODO: Replace this with the DFtoDuckDB IO Manager.
@asset(compute_kind="python", io_manager_key="io_manager")
def ingest_dataframe_to_duckdb(QIF_to_DF: Dict[str, Optional[pd.DataFrame]]) -> None:
    """
    Ingests a dictionary of Pandas DataFrames into a DuckDB database incrementally.

    Parameters (dict of Table_names & corresponding DFs):
    - table_name (str): The name of the table to create in DuckDB.
    - db_path (str): The path to the DuckDB database file. Default is ':memory:' for an in-memory database.

    Returns:
    - bool: True if successful, False otherwise.
    """
    schema: str = "landing"

    db_path = Path(DUCKDB_FILEPATH)

    # Initialize DuckDB connection
    with duckdb.connect(str(db_path)) as con:
        logger.debug("Connected to DuckDB")

        # Check if the table exists
        tables = con.execute("SHOW TABLES").fetchall()
        logger.debug(f"Existing tables: {tables}")

        column_names = ""

        for (
            table_name,
            df,
        ) in QIF_to_DF.items():  # Loop through all DataFrames in the dictionary
            if isinstance(df, pd.DataFrame) and not df.empty:
                try:
                    logger.debug(f"Processing table: {schema}.{table_name}")

                    if table_name not in [x[0] for x in tables]:
                        # Table doesn't exist, create it
                        con.register(table_name, df)
                        con.execute(
                            f"CREATE TABLE {schema}.{table_name} AS SELECT * FROM {table_name}"
                        )
                        logger.debug(f"Table {schema}.{table_name} created")
                    else:
                        # Table exists, check if composite_key column exists
                        columns = con.execute(
                            f"DESCRIBE {schema}.{table_name}"
                        ).fetchall()
                        logger.debug(
                            f"Existing columns in {schema}.{table_name}: {columns}"
                        )

                        if "composite_key" not in [x[0] for x in columns]:
                            # Add composite_key column
                            con.execute(
                                f"ALTER TABLE {schema}.{table_name} ADD COLUMN composite_key VARCHAR"
                            )
                            logger.debug("Composite_key column added")

                    # Get column names from DataFrame, excluding 'composite_key'
                    column_names = ", ".join(
                        [col for col in df.columns if col != "composite_key"]
                    )
                    logger.debug(f"Column names to be inserted: {column_names}")

                    # Register temp table and perform incremental load
                    temp_table_name = f"{schema}.{table_name}_temp"
                    con.register(temp_table_name, df)
                    logger.debug(f"Temporary table {temp_table_name} registered")

                    # Delete existing records that match the composite keys in the temp table
                    con.execute(
                        f"DELETE FROM {schema}.{table_name} WHERE composite_key IN (SELECT composite_key FROM {temp_table_name})"
                    )
                    logger.debug(
                        "Deleted existing records with matching composite_keys"
                    )

                    # Insert new records from the temp table into the main table
                    con.execute(
                        f"INSERT INTO {schema}.{table_name} ({column_names}) SELECT {column_names} FROM {temp_table_name}"
                    )
                    logger.debug(f"Inserted records into {schema}.{table_name}")

                    # Close the connection
                    con.close()
                    logger.debug("Connection closed")

                except Exception as e:
                    logger.info(f"An error occurred: {e}")



@asset(compute_kind="python", required_resource_keys={"pgConnection"})
def upload_dataframe_to_postgres(context, QIF_to_DF: Dict[str, Optional[pd.DataFrame]]) -> None:
    
    schema = 'landing'
    
    # Create a SQLAlchemy engine
    engine = create_engine(context.resources.postgres_db)
    
    # Upload the dataframe
    for table_name, df in QIF_to_DF.items():
        if df is not None:
            dtype = {
                'category': JSONB,  # Ensuring SQLAlchemy treats this column as JSONB
                'splits': JSONB
            }
            df.to_sql(name=table_name, con=engine, schema=schema, if_exists='replace', index=False, dtype=dtype)
            logger.info(f"Data uploaded successfully to {schema}.{table_name} table.")
        else:
            logger.error(f"No data to upload for {table_name}.")