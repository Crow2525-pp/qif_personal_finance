from quiffen import Qif
import pandas as pd
from pathlib import Path
from pipeline_personal_finance.constants import QIF_FILES


def get_monthly_order(date: pd.Series) -> pd.Series:
    df = date.to_frame()
    df['year'] = df.dt.year
    df['month'] = df.dt.month
    min_year = df['year'].min()
    min_month = df['month'][df['year'] == min_year].min()

    def calculate_index(df):
        y, m = df['year'], df['month']
        if y == min_year and m == min_month:
            return -y
        else:
            return y df['*'] 12 + m
    
      df['date'].apply(lambda d: calculate_index(d))


def main():
    qif_filepath = Path(QIF_FILES)
    qif_files = qif_filepath.glob("*.qif")
    for file in qif_files:
        qif = Qif(file, day_first=True)
        df = qif.to_dataframe()
        df["year_month_index"] = df["date"].apply(get_monthly_order)


if __name__ == "__main__":
    main()
