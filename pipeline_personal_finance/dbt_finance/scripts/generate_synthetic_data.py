import argparse
import csv
import os
from datetime import date, datetime, timedelta

ACCOUNTS = [
    ("ING_Countdown", "ING_Countdown_Transactions"),
    ("ING_BillsBillsBills", "ING_BillsBillsBills_Transactions"),
    ("Adelaide_Offset", "Adelaide_Offset_Transactions"),
    ("Adelaide_Homeloan", "Adelaide_Homeloan_Transactions"),
    ("Bendigo_Offset", "Bendigo_Offset_Transactions"),
    ("Bendigo_Homeloan", "Bendigo_Homeloan_Transactions"),
]

CATEGORY_MAPPINGS = [
    {
        "transaction_description": "PAYROLL",
        "transaction_type": "CREDIT",
        "sender": "ACME_PAYROLL",
        "recipient": "YOU",
        "category": "Salary",
        "subcategory": "Wages",
        "store": "Employer",
        "internal_indicator": "External",
    },
    {
        "transaction_description": "COLES",
        "transaction_type": "DEBIT",
        "sender": "YOU",
        "recipient": "COLES",
        "category": "Food & Drink",
        "subcategory": "Groceries",
        "store": "Coles",
        "internal_indicator": "External",
    },
    {
        "transaction_description": "UTIL",
        "transaction_type": "DEBIT",
        "sender": "YOU",
        "recipient": "UTILITY_CO",
        "category": "Household & Services",
        "subcategory": "Utilities",
        "store": "UtilityCo",
        "internal_indicator": "External",
    },
    {
        "transaction_description": "MORTGAGE PAYMENT",
        "transaction_type": "DEBIT",
        "sender": "YOU",
        "recipient": "BANK_MORTGAGE",
        "category": "Mortgage",
        "subcategory": "Home Loan",
        "store": "Mortgage",
        "internal_indicator": "External",
    },
    {
        "transaction_description": "INTEREST",
        "transaction_type": "INTEREST",
        "sender": "BANK_MORTGAGE",
        "recipient": "YOU",
        "category": "Mortgage",
        "subcategory": "Interest",
        "store": "Mortgage",
        "internal_indicator": "External",
    },
    {
        "transaction_description": "TRANSFER",
        "transaction_type": "DEBIT",
        "sender": "YOU",
        "recipient": "TRANSFER",
        "category": "Bank Transaction",
        "subcategory": "Internal Transfer",
        "store": "Internal",
        "internal_indicator": "Internal",
    },
    {
        "transaction_description": "AMAZON",
        "transaction_type": "DEBIT",
        "sender": "YOU",
        "recipient": "AMAZON",
        "category": "Shopping",
        "subcategory": "Online Retail",
        "store": "Amazon",
        "internal_indicator": "External",
    },
    {
        "transaction_description": "FAMILY",
        "transaction_type": "DEBIT",
        "sender": "YOU",
        "recipient": "FAMILY_ACTIVITY",
        "category": "Family & Kids",
        "subcategory": "Activities",
        "store": "Family",
        "internal_indicator": "External",
    },
    {
        "transaction_description": "HEALTH",
        "transaction_type": "DEBIT",
        "sender": "YOU",
        "recipient": "HEALTH_SHOP",
        "category": "Health & Beauty",
        "subcategory": "Pharmacy",
        "store": "Health",
        "internal_indicator": "External",
    },
    {
        "transaction_description": "LEISURE",
        "transaction_type": "DEBIT",
        "sender": "YOU",
        "recipient": "LEISURE_OUTLET",
        "category": "Leisure",
        "subcategory": "Entertainment",
        "store": "Leisure",
        "internal_indicator": "External",
    },
    {
        "transaction_description": "SHOPPING",
        "transaction_type": "DEBIT",
        "sender": "YOU",
        "recipient": "SHOPPING_MALL",
        "category": "Shopping",
        "subcategory": "Retail",
        "store": "Shopping",
        "internal_indicator": "External",
    },
    {
        "transaction_description": "TRANSPORT",
        "transaction_type": "DEBIT",
        "sender": "YOU",
        "recipient": "TRANSPORT_CO",
        "category": "Transport",
        "subcategory": "Public Transport",
        "store": "Transport",
        "internal_indicator": "External",
    },
]

CATEGORIES_ALLOWED = [
    ("Salary", 1),
    ("Food & Drink", 2),
    ("Household & Services", 3),
    ("Family & Kids", 4),
    ("Health & Beauty", 5),
    ("Leisure", 6),
    ("Shopping", 7),
    ("Transport", 8),
    ("Mortgage", 9),
    ("Bank Transaction", 10),
    ("Uncategorized", 99),
]

PROPERTY_ASSETS = [
    {
        "asset_id": "ppor",
        "asset_name": "PPOR_Property",
        "display_name": "Primary Residence",
        "asset_type": "Property",
        "purchase_date": "2018-06-15",
        "purchase_price": 650000,
        "appreciation_rate_low": 0.04,
        "appreciation_rate_high": 0.07,
        "currency_code": "AUD",
        "notes": "Synthetic asset",
    }
]

PROPERTY_VALUATION_OVERRIDES = [
    {
        "asset_id": "ppor",
        "valuation_date": "2024-01-01",
        "market_value": 780000,
        "currency_code": "AUD",
        "notes": "Synthetic override",
    }
]

MORTGAGE_PATCH_DATA = [
    {
        "date": "2023-06-15",
        "amount": -45,
        "line_number": 999001,
        "memo": "INTEREST",
        "bank_name": "Bendigo",
        "account_name": "Homeloan",
    }
]


def month_start(dt):
    return date(dt.year, dt.month, 1)


def iter_months(end_month_start, months_back):
    current = end_month_start
    for _ in range(months_back):
        yield current
        year = current.year
        month = current.month - 1
        if month == 0:
            month = 12
            year -= 1
        current = date(year, month, 1)


def write_csv(path, fieldnames, rows):
    with open(path, "w", newline="", encoding="ascii") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        for row in rows:
            writer.writerow(row)


def build_transactions(months_back):
    today = date.today()
    end_month = month_start(today.replace(day=1) - timedelta(days=1))
    end_month_index = end_month.year * 12 + end_month.month
    months = list(iter_months(end_month, months_back))
    data = {}
    for account_name, table_name in ACCOUNTS:
        rows = []
        line_number = 1
        for month in months:
            salary_date = month + timedelta(days=26)
            grocery_date = month + timedelta(days=6)
            util_date = month + timedelta(days=12)
            transfer_date = month + timedelta(days=18)
            mortgage_date = month + timedelta(days=24)
            bonus_date = month + timedelta(days=26)

            if account_name in ("ING_Countdown", "ING_BillsBillsBills"):
                rows.append(
                    make_txn(
                        account_name,
                        salary_date,
                        5000,
                        "PAYROLL ACME",
                        "PAYROLL",
                        "CREDIT",
                        "ACME_PAYROLL",
                        "YOU",
                        line_number,
                    )
                )
                line_number += 1
            rows.append(
                make_txn(
                    account_name,
                    grocery_date,
                    -220,
                    "COLES MARKET",
                    "COLES",
                    "DEBIT",
                    "YOU",
                    "COLES",
                    line_number,
                )
            )
            line_number += 1
            rows.append(
                make_txn(
                    account_name,
                    util_date,
                    -145,
                    "UTIL BILL",
                    "UTIL",
                    "DEBIT",
                    "YOU",
                    "UTILITY_CO",
                    line_number,
                )
            )
            line_number += 1
            rows.append(
                make_txn(
                    account_name,
                    transfer_date,
                    -800,
                    "TRANSFER TO OFFSET",
                    "TRANSFER",
                    "DEBIT",
                    "YOU",
                    "TRANSFER",
                    line_number,
                )
            )
            line_number += 1

            if "Homeloan" in account_name:
                rows.append(
                    make_txn(
                        account_name,
                        mortgage_date,
                        -2100,
                        "MORTGAGE PAYMENT",
                        "MORTGAGE PAYMENT",
                        "DEBIT",
                        "YOU",
                        "BANK_MORTGAGE",
                        line_number,
                    )
                )
                line_number += 1

            if account_name in ("ING_Countdown", "ING_BillsBillsBills"):
                is_recent = (month.year * 12 + month.month) >= (end_month_index - 5)
                shopping_amount = -250 if month == end_month else -95
                rows.append(
                    make_txn(
                        account_name,
                        grocery_date + timedelta(days=2),
                        -120,
                        "AMAZON ORDER",
                        "AMAZON",
                        "DEBIT",
                        "YOU",
                        "AMAZON",
                        line_number,
                    )
                )
                line_number += 1
                rows.append(
                    make_txn(
                        account_name,
                        util_date + timedelta(days=1),
                        -85,
                        "FAMILY ACTIVITY",
                        "FAMILY",
                        "DEBIT",
                        "YOU",
                        "FAMILY_ACTIVITY",
                        line_number,
                    )
                )
                line_number += 1
                rows.append(
                    make_txn(
                        account_name,
                        util_date + timedelta(days=3),
                        -65,
                        "HEALTH SHOP",
                        "HEALTH",
                        "DEBIT",
                        "YOU",
                        "HEALTH_SHOP",
                        line_number,
                    )
                )
                line_number += 1
                rows.append(
                    make_txn(
                        account_name,
                        transfer_date + timedelta(days=2),
                        -70,
                        "LEISURE OUTING",
                        "LEISURE",
                        "DEBIT",
                        "YOU",
                        "LEISURE_OUTLET",
                        line_number,
                    )
                )
                line_number += 1
                rows.append(
                    make_txn(
                        account_name,
                        transfer_date + timedelta(days=3),
                        shopping_amount,
                        "SHOPPING MALL",
                        "SHOPPING",
                        "DEBIT",
                        "YOU",
                        "SHOPPING_MALL",
                        line_number,
                    )
                )
                line_number += 1
                rows.append(
                    make_txn(
                        account_name,
                        transfer_date + timedelta(days=4),
                        -40,
                        "TRANSPORT FARE",
                        "TRANSPORT",
                        "DEBIT",
                        "YOU",
                        "TRANSPORT_CO",
                        line_number,
                    )
                )
                line_number += 1
                rows.append(
                    make_txn(
                        account_name,
                        transfer_date + timedelta(days=5),
                        -55,
                        "MISC PURCHASE",
                        "UNKNOWN",
                        "DEBIT",
                        "YOU",
                        "MISC_VENDOR",
                        line_number,
                    )
                )
                line_number += 1
                if is_recent:
                    rows.append(
                        make_txn(
                            account_name,
                            transfer_date + timedelta(days=6),
                            -1500,
                            "UNCAT LARGE",
                            "UNCAT_LARGE",
                            "UNKNOWN",
                            "YOU",
                            "MISC_VENDOR",
                            line_number,
                        )
                    )
                    line_number += 1

            if "Offset" in account_name:
                rows.append(
                    make_txn(
                        account_name,
                        transfer_date + timedelta(days=1),
                        800,
                        "TRANSFER FROM COUNTDOWN",
                        "TRANSFER",
                        "CREDIT",
                        "TRANSFER",
                        "YOU",
                        line_number,
                    )
                )
                line_number += 1

            if account_name not in ("ING_Countdown", "ING_BillsBillsBills"):
                rows.append(
                    make_txn(
                        account_name,
                        bonus_date,
                        4000,
                        "PAYROLL BONUS",
                        "PAYROLL",
                        "CREDIT",
                        "ACME_PAYROLL",
                        "YOU",
                        line_number,
                    )
                )
                line_number += 1

        data[table_name] = rows
    return data


def make_txn(
    account_name,
    transaction_date,
    amount,
    memo,
    description,
    transaction_type,
    sender,
    recipient,
    line_number,
):
    primary_key = f"{account_name}-{transaction_date.isoformat()}-{line_number}"
    return {
        "primary_key": primary_key,
        "transaction_date": transaction_date.isoformat(),
        "memo": memo,
        "receipt": "",
        "location": "",
        "description_date": "",
        "card_no": "",
        "sender": sender,
        "recipient": recipient,
        "transaction_description": description,
        "transaction_type": transaction_type,
        "transaction_amount": amount,
        "line_number": line_number,
        "etl_date": transaction_date.isoformat(),
        "etl_time": "00:00:00+00",
        "account_name": account_name,
    }


def build_known_values(transactions):
    rows = []
    for account_name, table_name in ACCOUNTS:
        sample_row = transactions[table_name][0]
        rows.append(
            {
                "account_name": account_name,
                "specific_date": sample_row["transaction_date"],
                "account_balance": 10000,
                "is_asset": "true" if "Homeloan" not in account_name else "false",
                "is_liquid_asset": "true" if "Offset" in account_name else "false",
                "is_loan": "true" if "Homeloan" in account_name else "false",
                "is_homeloan": "true" if "Homeloan" in account_name else "false",
                "is_debt": "true" if "Homeloan" in account_name else "false",
            }
        )
    return rows


def build_banking_categories():
    rows = []
    for account_name, _table_name in ACCOUNTS:
        for mapping in CATEGORY_MAPPINGS:
            rows.append(
                {
                    "transaction_description": mapping["transaction_description"],
                    "transaction_type": mapping["transaction_type"],
                    "sender": mapping["sender"],
                    "recipient": mapping["recipient"],
                    "account_name": account_name,
                    "category": mapping["category"],
                    "subcategory": mapping["subcategory"],
                    "store": mapping["store"],
                    "internal_indicator": mapping["internal_indicator"],
                }
            )
    return rows


def build_categories_allowed():
    return [
        {"category": category, "display_order": display_order}
        for category, display_order in CATEGORIES_ALLOWED
    ]


def main():
    parser = argparse.ArgumentParser(description="Generate synthetic seed data.")
    parser.add_argument(
        "--output-dir",
        default=os.path.join("pipeline_personal_finance", "dbt_finance", "seeds", "local"),
        help="Output directory for generated CSVs.",
    )
    parser.add_argument("--months", type=int, default=24, help="Number of months to generate.")
    args = parser.parse_args()

    os.makedirs(args.output_dir, exist_ok=True)

    transactions = build_transactions(args.months)
    txn_fields = [
        "primary_key",
        "transaction_date",
        "memo",
        "receipt",
        "location",
        "description_date",
        "card_no",
        "sender",
        "recipient",
        "transaction_description",
        "transaction_type",
        "transaction_amount",
        "line_number",
        "etl_date",
        "etl_time",
        "account_name",
    ]

    for table_name, rows in transactions.items():
        path = os.path.join(args.output_dir, f"{table_name}.csv")
        write_csv(path, txn_fields, rows)

    known_values = build_known_values(transactions)
    write_csv(
        os.path.join(args.output_dir, "known_values.csv"),
        [
            "account_name",
            "specific_date",
            "account_balance",
            "is_asset",
            "is_liquid_asset",
            "is_loan",
            "is_homeloan",
            "is_debt",
        ],
        known_values,
    )

    write_csv(
        os.path.join(args.output_dir, "banking_categories.csv"),
        [
            "transaction_description",
            "transaction_type",
            "sender",
            "recipient",
            "account_name",
            "category",
            "subcategory",
            "store",
            "internal_indicator",
        ],
        build_banking_categories(),
    )

    write_csv(
        os.path.join(args.output_dir, "categories_allowed.csv"),
        ["category", "display_order"],
        build_categories_allowed(),
    )

    write_csv(
        os.path.join(args.output_dir, "property_assets.csv"),
        list(PROPERTY_ASSETS[0].keys()),
        PROPERTY_ASSETS,
    )

    write_csv(
        os.path.join(args.output_dir, "property_valuation_overrides.csv"),
        list(PROPERTY_VALUATION_OVERRIDES[0].keys()),
        PROPERTY_VALUATION_OVERRIDES,
    )

    write_csv(
        os.path.join(args.output_dir, "mortgage_patch_data.csv"),
        list(MORTGAGE_PATCH_DATA[0].keys()),
        MORTGAGE_PATCH_DATA,
    )

    print(f"Synthetic seed data written to: {args.output_dir}")


if __name__ == "__main__":
    main()
