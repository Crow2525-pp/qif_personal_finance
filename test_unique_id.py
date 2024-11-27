from quiffen import Qif
import pandas as pd
from pathlib import Path
from pipeline_personal_finance.definitions import QIF_FILES


def get_monthly_order(date: pd.Series) -> pd.Series:
    date = pd.to_dataframe(date)
    year = date.dt.year
    month = date.dt.month
    min_year = year.min()
    min_month = month[year == min_year].min()

    def calculate_index(d):
        y, m = d.year, d.month
        if y == min_year and m == min_month:
            return -y
        else:
            return y * 12 + m

    return date.apply(lambda d: calculate_index(d))


def main():
    qif_filepath = Path(QIF_FILES)
    qif_files = qif_filepath.glob("*.qif")
    for file in qif_files:
        qif = Qif(file, day_first=True)
        df = qif.to_dataframe()
        df["year_month_index"] = df["date"].apply(get_monthly_order)


if __name__ == "__main__":
    main()
