import pandas as pd
import matplotlib.pyplot as plt
from pathlib import Path
from datetime import datetime

PROJECT_ROOT = Path(__file__).resolve().parent.parent
QIF_DIR = PROJECT_ROOT / "pipeline_personal_finance" / "qif_files"
OUTPUT_DIR = Path(__file__).resolve().parent


def parse_qif_file(path: Path) -> list[dict]:
    records = []
    bank, account, _, date_str = path.stem.split("_")
    extract_date = datetime.strptime(date_str, "%Y%m%d").date()

    with path.open() as file:
        current = {"bank": bank, "account": account, "extract_date": extract_date}
        for raw_line in file:
            line = raw_line.rstrip("\n")
            if not line or line.startswith("!"):
                continue
            if line == "^":
                if "date" in current and "amount" in current:
                    records.append(current)
                current = {"bank": bank, "account": account, "extract_date": extract_date}
                continue

            key, value = line[0], line[1:]
            if key == "D":
                try:
                    current["date"] = datetime.strptime(value, "%d/%m/%Y").date()
                except ValueError:
                    current["date"] = datetime.strptime(value, "%d/%m/%y").date()
            elif key == "T":
                current["amount"] = float(value.replace(",", ""))
            elif key == "P":
                current["payee"] = value.strip()
            elif key == "M":
                current["memo"] = value.strip()
            elif key == "L":
                current["category"] = value.strip()
            else:
                extras = current.setdefault("extra", [])
                extras.append(line)

    return records


def load_transactions() -> pd.DataFrame:
    all_records: list[dict] = []
    for path in sorted(QIF_DIR.glob("*.qif")):
        all_records.extend(parse_qif_file(path))
    transactions = pd.DataFrame(all_records)
    transactions["date"] = pd.to_datetime(transactions["date"], format="%Y-%m-%d")
    transactions["year_month"] = transactions["date"].dt.to_period("M")
    return transactions


def build_monthly_summary(transactions: pd.DataFrame) -> pd.DataFrame:
    latest_month = transactions["year_month"].max()
    window = pd.period_range(latest_month - 2, latest_month, freq="M")
    windowed = transactions[transactions["year_month"].isin(window)]

    group_cols = ["year_month", "bank", "account"]
    summary = (
        windowed
        .groupby(group_cols)
        .agg(
            transactions=("amount", "size"),
            inflow=("amount", lambda x: x[x > 0].sum()),
            outflow=("amount", lambda x: x[x < 0].sum()),
            net=("amount", "sum"),
        )
        .reset_index()
        .sort_values(group_cols)
    )
    summary["inflow"] = summary["inflow"].fillna(0.0)
    summary["outflow"] = summary["outflow"].fillna(0.0)
    return summary


def write_markdown(overall: pd.DataFrame, account_summary: pd.DataFrame, output_file: Path) -> None:
    lines: list[str] = []
    lines.append("# Cashflow Snapshot (Last 3 Months)\n")

    latest_period = overall.index.max()
    earliest_period = overall.index.min()
    lines.append(
        f"Data window: {earliest_period.strftime('%b %Y')} to {latest_period.strftime('%b %Y')}\n\n"
    )

    lines.append("## Overall Cashflow\n")
    lines.append("| Month | Inflow | Outflow | Net | Transactions |\n")
    lines.append("| --- | ---: | ---: | ---: | ---: |\n")
    for period, row in overall.iterrows():
        lines.append(
            f"| {period.strftime('%b %Y')} | $ {row['inflow']:,.2f} | $ {row['outflow']:,.2f} | $ {row['net']:,.2f} | {int(row['transactions'])} |\n"
        )

    lines.append("\n## Net Cashflow by Account\n")
    lines.append("| Month | Bank | Account | Net | Inflow | Outflow | Txns |\n")
    lines.append("| --- | --- | --- | ---: | ---: | ---: | ---: |\n")
    for _, row in account_summary.iterrows():
        lines.append(
            f"| {row['year_month']} | {row['bank']} | {row['account']} | $ {row['net']:,.2f} | $ {row['inflow']:,.2f} | $ {row['outflow']:,.2f} | {int(row['transactions'])} |\n"
        )

    lines.append("\n## Highlights\n")
    net_series = overall["net"]
    mom_changes = net_series.diff()
    biggest_swing = mom_changes.abs().idxmax()
    lines.append(
        f"- Month-over-month swing: {biggest_swing.strftime('%b %Y')} shifted by $ {mom_changes.loc[biggest_swing]:,.2f} compared to the prior month.\n"
    )

    if (account_summary["account"].str.contains("Offset")).any():
        offsets = account_summary[account_summary["account"].str.contains("Offset")]
        offset_totals = offsets.groupby("year_month")["net"].sum()
        lines.append(
            "- Savings contribution (Offset accounts): "
            + ", ".join(
                f"{period}: $ {value:,.2f}" for period, value in offset_totals.items()
            )
            + "\n"
        )

    top_credit = account_summary.sort_values("net", ascending=False).head(1).iloc[0]
    top_debit = account_summary.sort_values("net").head(1).iloc[0]
    lines.append(
        f"- Largest positive month: {top_credit['year_month']} {top_credit['bank']} {top_credit['account']} net $ {top_credit['net']:,.2f}.\n"
    )
    lines.append(
        f"- Largest negative month: {top_debit['year_month']} {top_debit['bank']} {top_debit['account']} net $ {top_debit['net']:,.2f}.\n"
    )

    output_file.write_text("".join(lines))


def plot_dashboard(overall: pd.DataFrame, account_summary: pd.DataFrame, output_file: Path) -> None:
    plt.style.use("seaborn-v0_8-darkgrid")
    fig, axes = plt.subplots(2, 1, figsize=(10, 8), constrained_layout=True)

    months = overall.index.to_timestamp()
    axes[0].bar(months, overall["inflow"], width=18, label="Inflow", color="#4caf50")
    axes[0].bar(months, overall["outflow"], width=18, label="Outflow", color="#f44336")
    axes[0].plot(months, overall["net"], marker="o", color="#2196f3", label="Net")
    axes[0].set_title("Overall Monthly Cashflow")
    axes[0].set_ylabel("Amount ($)")
    axes[0].legend()

    for account, group in account_summary.groupby("account"):
        axes[1].plot(
            pd.PeriodIndex(group["year_month"], freq="M").to_timestamp(),
            group["net"],
            marker="o",
            label=account,
        )
    axes[1].axhline(0, color="black", linewidth=0.8)
    axes[1].set_title("Net Cashflow by Account")
    axes[1].set_ylabel("Net ($)")
    axes[1].legend()

    fig.suptitle("Cashflow Trend - Last 3 Months", fontsize=14)
    fig.savefig(output_file, dpi=200)
    plt.close(fig)


def main() -> None:
    transactions = load_transactions()
    account_summary = build_monthly_summary(transactions)

    overall = (
        account_summary
        .groupby("year_month")
        .agg(
            inflow=("inflow", "sum"),
            outflow=("outflow", "sum"),
            net=("net", "sum"),
            transactions=("transactions", "sum"),
        )
    )

    markdown_path = OUTPUT_DIR / "cashflow_last_3_months.md"
    chart_path = OUTPUT_DIR / "cashflow_last_3_months.png"

    write_markdown(overall, account_summary, markdown_path)
    plot_dashboard(overall, account_summary, chart_path)


if __name__ == "__main__":
    main()
