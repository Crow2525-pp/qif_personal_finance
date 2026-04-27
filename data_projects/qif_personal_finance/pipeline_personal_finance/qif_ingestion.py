from __future__ import annotations

import datetime as dt
import re
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import pandas as pd


_QIF_FILENAME_PATTERN = re.compile(
    r"^(?P<bank_name>[A-Za-z0-9-]+)_(?P<account_name>[A-Za-z0-9_-]+)_Transactions_(?P<extract_date>\d{8})$"
)


@dataclass(frozen=True, slots=True)
class QifFilenameParts:
    bank_name: str
    account_name: str
    extract_date: str


def validate_date_format(date_str: str) -> bool:
    try:
        parsed = dt.datetime.strptime(date_str, "%Y%m%d")
    except ValueError:
        return False
    return parsed.strftime("%Y%m%d") == date_str


def validate_identifier(value: str, field_name: str) -> None:
    """Validate that an identifier contains only safe alphanumeric characters.

    This prevents SQL injection by ensuring identifiers used in table names
    contain only letters, numbers, underscores, and hyphens.

    Args:
        value: The identifier value to validate
        field_name: Name of the field for error messages

    Raises:
        ValueError: If the identifier contains unsafe characters
    """
    if not value:
        raise ValueError(f"{field_name} cannot be empty")

    # Allow alphanumeric, underscores, and hyphens only
    # Explicitly reject quotes, semicolons, and other SQL special characters
    if not all(c.isalnum() or c in ('_', '-') for c in value):
        raise ValueError(
            f"{field_name} '{value}' contains invalid characters. "
            "Only letters, numbers, underscores, and hyphens are allowed."
        )


def parse_qif_filename(filename: str | Path) -> QifFilenameParts:
    stem = Path(filename).stem
    match = _QIF_FILENAME_PATTERN.fullmatch(stem)
    if not match:
        raise ValueError(
            "Filename format must be 'BankName_AccountName_Transactions_YYYYMMDD.qif'"
        )

    bank_name = match.group("bank_name")
    account_name = match.group("account_name")
    extract_date = match.group("extract_date")

    # Validate identifiers to prevent SQL injection
    validate_identifier(bank_name, "bank_name")
    validate_identifier(account_name, "account_name")

    if not validate_date_format(extract_date):
        raise ValueError(
            f"Invalid date format in filename: {extract_date}. Must be a real YYYYMMDD date"
        )

    return QifFilenameParts(
        bank_name=bank_name,
        account_name=account_name,
        extract_date=extract_date,
    )


def add_filename_data_to_dataframe(filename: str, dataframe: pd.DataFrame) -> pd.DataFrame:
    parts = parse_qif_filename(filename)
    dataframe["BankName"] = parts.bank_name
    dataframe["AccountName"] = parts.account_name
    dataframe["Extract_Date"] = parts.extract_date
    return dataframe


def is_qif_file(path: str | Path) -> bool:
    return Path(path).suffix.lower() == ".qif"


def sort_qif_files(files: Iterable[Path]) -> list[Path]:
    return sorted(
        files,
        key=lambda file_path: (
            parse_qif_filename(file_path.name).extract_date,
            file_path.name.lower(),
        ),
    )


def discover_qif_files(directory: Path) -> list[Path]:
    if not directory.exists():
        return []

    candidates: list[Path] = []
    for path in directory.iterdir():
        if not path.is_file() or not is_qif_file(path):
            continue
        try:
            parse_qif_filename(path.name)
        except ValueError:
            continue
        candidates.append(path)

    return sort_qif_files(candidates)


def union_unique(
    df1: pd.DataFrame,
    df2: pd.DataFrame,
    unique_column: str,
    *,
    order_column: str = "Extract_Date",
) -> pd.DataFrame:
    combined = pd.concat([df1, df2], ignore_index=True)

    if order_column in combined.columns:
        combined = combined.sort_values(by=[order_column], kind="stable")
        return combined.drop_duplicates(subset=unique_column, keep="last")

    return combined.drop_duplicates(subset=unique_column)


def duplicate_key_summary(
    dataframe: pd.DataFrame,
    unique_column: str,
    *,
    limit: int = 5,
) -> str:
    duplicates = dataframe[dataframe.duplicated(subset=unique_column, keep=False)]
    if duplicates.empty:
        return ""

    sample_keys = duplicates[unique_column].drop_duplicates().head(limit).tolist()
    key_list = ", ".join(str(key) for key in sample_keys)
    return (
        f"{len(duplicates)} duplicate rows across "
        f"{duplicates[unique_column].nunique()} duplicate keys"
        f"; sample keys: {key_list}"
    )


def assert_unique_primary_keys(
    dataframe: pd.DataFrame,
    unique_column: str,
    *,
    bank_name: str,
    account_name: str,
) -> None:
    summary = duplicate_key_summary(dataframe, unique_column)
    if summary:
        raise ValueError(
            f"Duplicate primary keys detected for {bank_name}/{account_name}: {summary}"
        )
