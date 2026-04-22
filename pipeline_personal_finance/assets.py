import os
from pathlib import Path
import hashlib
import json
import pandas as pd
import numpy as np
from quiffen import Qif
from dagster import (
    AssetDep,
    AssetExecutionContext,
    AssetOut,
    MetadataValue,
    Output,
    multi_asset,
)
from dagster_dbt import DagsterDbtTranslator, DbtCliResource, dbt_assets
from sqlalchemy import text, JSON
from typing import Any, Mapping, Optional
from .constants import dbt_manifest_path, QIF_FILES
from .qif_ingestion import (
    add_filename_data_to_dataframe,
    assert_unique_primary_keys,
    sort_qif_files,
    union_unique,
)
from .resources import SqlAlchemyClientResource

# TODO: Incremental Refresh
# TODO: Unique Indentifiers -
#   Group transactions by month.
# Assign a unique identifier to each transaction based on its description, amount, date, and its index within the group.
# TODO: Add Monitoring of new QIF Files within dir.


class _FinanceDbtTranslator(DagsterDbtTranslator):
    """Maps dbt model folder paths to Dagster asset groups."""

    def get_group_name(self, dbt_resource_props: Mapping[str, Any]) -> Optional[str]:
        resource_type = dbt_resource_props.get("resource_type", "")
        if resource_type == "snapshot":
            return "snapshots"
        if resource_type == "seed":
            return "seeds"
        fqn = dbt_resource_props.get("fqn", [])
        # fqn: ['project_name', 'folder', ..., 'model_name']
        # Use the top-level folder (index 1) as the Dagster group.
        if len(fqn) >= 2:
            return fqn[1]
        return "default"


# TODO: Move dbt_assets to a seperate file?
@dbt_assets(
    manifest=dbt_manifest_path,
    dagster_dbt_translator=_FinanceDbtTranslator(),
)
def finance_dbt_assets(context: AssetExecutionContext, dbt: DbtCliResource):
    # TODO: find out why dagster_deployment env var is not working. Fixed as Prod for moment.
    deployment_name = os.getenv("DAGSTER_DEPLOYMENT", "prod")
    target = "prod" if deployment_name == "prod" else "dev"
    yield from dbt.cli(
        ["build", "--target", target],
        context=context,
    ).stream()


def hash_concat_row_wise(df: pd.DataFrame) -> pd.Series:
    hash_columns = [
        "BankName",
        "AccountName",
        "date",
        "amount",
        "memo",
        "transaction_description",
        "transaction_type",
        "sender",
        "recipient",
        "month_order",
    ]

    def normalize_value(value: Any) -> Any:
        if pd.isna(value):
            return None
        if isinstance(value, pd.Timestamp):
            return value.isoformat()
        return str(value).strip()

    def hash_row(row):
        payload = {
            column: normalize_value(row[column])
            for column in hash_columns
            if column in row.index
        }
        concatenated_values = json.dumps(payload, sort_keys=True, separators=(",", ":"))
        hash_obj = hashlib.sha256(concatenated_values.encode())
        hash_hex = hash_obj.hexdigest()
        return hash_hex

    return df.apply(hash_row, axis=1)


def add_incremental_row_number(
    df: pd.DataFrame, date_col: str = "date", line_col="line_number"
) -> pd.DataFrame:
    df[date_col] = pd.to_datetime(df[date_col])

    df["year"] = df[date_col].dt.year
    df["month"] = df[date_col].dt.month

    df["earliest_month"] = df.groupby("year")["month"].transform("min")

    df["is_earliest_month"] = df["month"] == df["earliest_month"]

    df["date_int"] = df[date_col].astype("int64")

    # This section inverts the date to make the dadtum point the end of the month
    # for the earliest month because the dataset will be cropped at the tail
    # and expand at the head.

    df["date_order"] = np.where(
        df["is_earliest_month"],
        -df["date_int"],  # negate for earliest month
        df["date_int"],
    )

    df["line_order"] = np.where(
        df["is_earliest_month"],
        -df[line_col],  # negate for earliest month
        df[line_col],
    )
    df = df.sort_values(
        by=["year", "is_earliest_month", "month", "date_order", "line_order"],
        ascending=[True, False, True, True, True],
    )

    df["month_order"] = df.groupby(["year", "month"]).cumcount() + 1

    df.drop(
        columns=[
            # "year",
            # "month",
            "earliest_month",
            "is_earliest_month",
            "line_order",
            "date_order",
            "date_int",
        ],
        inplace=True,
    )

    return df


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
            # Log which database we're connected to
            context.log.debug(f"Executing: {check_db_sql}")
            db_result = conn.execute(text(check_db_sql)).fetchone()
            current_db = db_result[0] if db_result else "Unknown"
            context.log.debug(f"Connected to database: {current_db}")

            # Check if Schema is in DB Information Schema
            context.log.debug(f"Checking schema with: {verify_schema_sql}")
            result = conn.execute(text(verify_schema_sql)).fetchone()
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


_INGESTION_TAGS = {"dagster/kind/python": "", "dagster/kind/postgres": ""}

@multi_asset(
    outs={
        "Adelaide_Homeloan_Transactions": AssetOut(is_required=False, tags=_INGESTION_TAGS),
        "Adelaide_Offset_Transactions": AssetOut(is_required=False, tags=_INGESTION_TAGS),
        "Bendigo_Homeloan_Transactions": AssetOut(is_required=False, tags=_INGESTION_TAGS),
        "Bendigo_Offset_Transactions": AssetOut(is_required=False, tags=_INGESTION_TAGS),
        "ING_BillsBillsBills_Transactions": AssetOut(is_required=False, tags=_INGESTION_TAGS),
        "ING_Countdown_Transactions": AssetOut(is_required=False, tags=_INGESTION_TAGS),
    },
    deps=[AssetDep("postgres_role_readiness_gate")],
    can_subset=True,
    group_name="qif_ingestion",
)
def upload_dataframe_to_database(
    context: AssetExecutionContext, personal_finance_database: SqlAlchemyClientResource
):
    qif_filepath = Path(QIF_FILES)
    qif_files = sort_qif_files(qif_filepath.glob("*.qif"))

    grouped_dataframes = {}

    for file in qif_files:
        qif = Qif.parse(str(file), day_first=True)
        df = qif.to_dataframe()
        df_indexed = add_incremental_row_number(df, "date", "line_number")

        df_filename = add_filename_data_to_dataframe(
            filename=file.name, dataframe=df_indexed
        )
        df_filename["primary_key"] = hash_concat_row_wise(df_filename)

        bank_name = df_filename["BankName"].iloc[0]
        account_name = df_filename["AccountName"].iloc[0]
        extract_date = df_filename["Extract_Date"].iloc[0]
        key = (bank_name, account_name)

        if key in grouped_dataframes:
            context.log.info(
                f"Combining data for bank={bank_name} account={account_name} "
                f"extract_date={extract_date}"
            )
            grouped_dataframes[key] = union_unique(
                grouped_dataframes[key],
                df_filename,
                unique_column="primary_key",
            )
        else:
            grouped_dataframes[key] = df_filename

    for (bank, account), dataframe in grouped_dataframes.items():
        assert_unique_primary_keys(
            dataframe,
            "primary_key",
            bank_name=bank,
            account_name=account,
        )

        unique_extract_dates = dataframe["Extract_Date"].unique().tolist()
        context.log.info(
            f"Prepared {len(dataframe)} rows for bank={bank} account={account} "
            f"across extract dates={unique_extract_dates}"
        )

        table_name = bank + "_" + account + "_Transactions"

        schema = "landing"
        verify_database_schema(context, personal_finance_database, schema)

        dtype = {
            "category": JSON,
            "splits": JSON,
        }

        # Upload the dataframe
        if dataframe is not None:
            try:
                with personal_finance_database.get_connection() as conn:
                    table_exists = conn.execute(
                        text(
                            """
                            SELECT 1
                            FROM information_schema.tables
                            WHERE table_schema = :schema
                              AND table_name = :table_name
                            """
                        ),
                        {"schema": schema, "table_name": table_name},
                    ).scalar()
                    if_exists_mode = "replace"
                    if table_exists:
                        conn.execute(
                            text(f'TRUNCATE TABLE "{schema}"."{table_name}"')
                        )
                        if_exists_mode = "append"

                    dataframe.to_sql(
                        name=table_name,
                        con=conn,
                        schema=schema,
                        if_exists=if_exists_mode,
                        index=False,
                        dtype=dtype,
                    )
                    conn.commit()

                context.add_output_metadata(
                    metadata={
                        "data_types": MetadataValue.md(dataframe.dtypes.to_markdown()),
                        "num_records": len(dataframe),
                        "preview": MetadataValue.md(dataframe.head().to_markdown()),
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
