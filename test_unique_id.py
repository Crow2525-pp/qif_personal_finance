from quiffen import Qif
import pandas as pd
import numpy as np
from pathlib import Path
from pipeline_personal_finance.constants import QIF_FILES
import re
from typing import Optional
import hashlib


def create_primary_key(row):
    concatenated_values = f"{row['year']};{row['month']};{row['month_order']}"

    # return concatenated_values
    return hashlib.md5(concatenated_values.encode()).hexdigest()


def add_incremental_row_number(
    df: pd.DataFrame, date_col: str = "date", line_col="line_number"
) -> pd.DataFrame:
    df[date_col] = pd.to_datetime(df[date_col])

    df["year"] = df[date_col].dt.year
    df["month"] = df[date_col].dt.month

    df["earliest_month"] = df.groupby("year")["month"].transform("min")

    df["is_earliest_month"] = df["month"] == df["earliest_month"]

    df["date_int"] = df[date_col].view("int64")

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


def validate_date_format(date_str: str) -> bool:
    return bool(re.match(r"^\d{4}(0[1-9]|1[0-2])(0[1-9]|[12][0-9]|3[01])$", date_str))


def add_filename_data_to_dataframe(
    filename: str, dataframe: pd.DataFrame
) -> pd.DataFrame:
    base_name = filename.rsplit(".", 1)[0]

    parts = base_name.split("_")

    if len(parts) != 4 or parts[2] != "Transactions":
        raise ValueError(
            "Filename format must be 'BankName_AccountName_Transactions_YYYYMMDD"
        )

    bank_name, account_name, _, dates = parts

    if not validate_date_format(dates):
        raise ValueError(
            f"Invalid date format in filename: {dates}. Must be in YYYYMMDD format"
        )

    dataframe["BankName"] = bank_name
    dataframe["AccountName"] = account_name
    dataframe["Extract_Date"] = dates

    return dataframe


def union_unique(
    df1: pd.DataFrame, df2: pd.DataFrame, unique_column: str
) -> Optional[pd.DataFrame]:
    combined = pd.concat([df1, df2], ignore_index=True)

    unique_combined = combined.drop_duplicates(subset=unique_column)

    return unique_combined


def main():
    qif_filepath = Path(QIF_FILES)
    qif_files = qif_filepath.glob("*.qif")

    grouped_dataframes = {}

    for file in qif_files:
        qif = Qif.parse(file, day_first=True)
        df = qif.to_dataframe()
        df_indexed = add_incremental_row_number(df, "date", "line_number")
        df_indexed["origin_key"] = df_indexed.apply(create_primary_key, axis=1)

        df_filename = add_filename_data_to_dataframe(
            filename=file.name, dataframe=df_indexed
        )

        bank_name = df_filename["BankName"].iloc[0]
        account_name = df_filename["AccountName"].iloc[0]
        extract_date = df_filename["Extract_Date"].iloc[0]
        key = (bank_name, account_name)

        if key in grouped_dataframes:
            print(
                f"Combining data for bank: {bank_name}, account: {account_name}, for extract date: {extract_date}"
            )
            grouped_dataframes[key] = union_unique(
                grouped_dataframes[key], df_filename, unique_column="origin_key"
            )
        else:
            grouped_dataframes[key] = df_filename

    for (bank, account), dataframe in grouped_dataframes.items():

        if dataframe["origin_key"].is_unique:
            print("no duplicates found")
        else:
            duplicates = dataframe[
                dataframe.duplicated(subset="origin_key", keep=False)
            ]
            print(f"Duplicate rows: \n{duplicates}")
            raise ValueError("The primary key contains duplicate values")

        print(f"Final dataframe for bank: {bank}, account: {account}")
        print(dataframe.head())
        unique_extract_dates = dataframe["Extract_Date"].unique()
        print(f"Unique dates: {unique_extract_dates}")


if __name__ == "__main__":
    main()
