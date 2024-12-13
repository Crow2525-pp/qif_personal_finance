from datetime import date
from quiffen import Qif
import pandas as pd
import numpy as np
from pathlib import Path
from pipeline_personal_finance.constants import QIF_FILES


def add_incremental_row_number(
    df: pd.DataFrame, date_col: str = "date", line_col="line_number"
) -> pd.DataFrame:
    df[date_col] = pd.to_datetime(df[date_col])

    df["year"] = df[date_col].dt.year
    df["month"] = df[date_col].dt.month

    df["earliest_month"] = df.groupby("year")["month"].transform("min")

    df["is_earliest_month"] = df["month"] == df["earliest_month"]

    df["date_int"] = df[date_col].view("int64")

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
            "year",
            "month",
            "earliest_month",
            # 'is_earliest_month',
            #  "line_order",
        ],
        inplace=True,
    )

    return df


# def get_monthly_order(date: pd.Series) -> pd.Series:
#     df = date.to_frame()
#     df["year"] = df.dt.year
#     df["month"] = df.dt.month
#     min_year = df["year"].min()
#     min_month = df["month"][df["year"] == min_year].min()
#
#     def calculate_index(df):
#         y, m = df["year"], df["month"]
#         if y == min_year and m == min_month:
#             return -y
#         else:
#             return y
#
#     df["date"].apply(lambda d: calculate_index(d))


def main():
    qif_filepath = Path(QIF_FILES)
    qif_files = qif_filepath.glob("*.qif")
    for file in qif_files:
        qif = Qif.parse(file, day_first=True)
        df = qif.to_dataframe()
        # df["year_month_index"] = df["date"].apply(get_monthly_order)
        df_indexed = add_incremental_row_number(df, "date", "line_number")
        print(df_indexed.head())


if __name__ == "__main__":
    main()
