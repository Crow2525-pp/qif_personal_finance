from datetime import date
from quiffen import Qif
import pandas as pd
import numpy as np
from pathlib import Path
from pipeline_personal_finance.constants import QIF_FILES
import hashlib


def create_primary_key(row):
    concatenated_values = f"{row['year']};{row['month']};{row['month_order']}"

    return concatenated_values
    # return hashlib.md5(concatenated_values.encode()).hexdigest()


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


def union_unique(
    df1: pd.DataFrame, df2: pd.DataFrame, unique_column: str
) -> pd.Dataframe:
    combined = pd.concat([df1, df2], ignore_index=True)

    unique_combined = combined.drop_duplicates(subset=unique_column)

    return unique_combined


def main():
    qif_filepath = Path(QIF_FILES)
    qif_files = qif_filepath.glob("*.qif")
    for file in qif_files:
        qif = Qif.parse(file, day_first=True)
        df = qif.to_dataframe()
        # df["year_month_index"] = df["date"].apply(get_monthly_order)
        df_indexed = add_incremental_row_number(df, "date", "line_number")
        df_indexed["origin_key"] = df_indexed.apply(create_primary_key, axis=1)

        if df_indexed["origin_key"].is_unique:
            print("no duplicates found")
        else:
            duplicates = df[df.duplicated(subset="origin_key", keep=False)]
            print(f"Duplicate rows: \n{duplicates}")
            raise ValueError("The primary key contains duplicate values")

        print(df_indexed.head())


if __name__ == "__main__":
    main()
