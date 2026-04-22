from __future__ import annotations

from pathlib import Path

import pandas as pd
import pytest

from pipeline_personal_finance.qif_ingestion import (
    add_filename_data_to_dataframe,
    assert_unique_primary_keys,
    parse_qif_filename,
    sort_qif_files,
    union_unique,
    validate_date_format,
)


def test_validate_date_format_rejects_impossible_calendar_dates():
    assert validate_date_format("20260228") is True
    assert validate_date_format("20260230") is False
    assert validate_date_format("20261301") is False


def test_parse_qif_filename_allows_underscores_in_account_name():
    parts = parse_qif_filename("ING_My_New_Account_Transactions_20260422.qif")

    assert parts.bank_name == "ING"
    assert parts.account_name == "My_New_Account"
    assert parts.extract_date == "20260422"


def test_parse_qif_filename_rejects_invalid_structure_with_clear_error():
    with pytest.raises(
        ValueError,
        match=r"Filename format must be 'BankName_AccountName_Transactions_YYYYMMDD\.qif'",
    ):
        parse_qif_filename("ING_Countdown_20260422.qif")


def test_parse_qif_filename_rejects_impossible_dates_with_clear_error():
    with pytest.raises(
        ValueError,
        match=r"Invalid date format in filename: 20260230\. Must be a real YYYYMMDD date",
    ):
        parse_qif_filename("ING_Countdown_Transactions_20260230.qif")


def test_add_filename_data_to_dataframe_adds_metadata_columns():
    dataframe = pd.DataFrame({"amount": [10.5]})

    enriched = add_filename_data_to_dataframe(
        "ING_Countdown_Transactions_20260422.qif", dataframe.copy()
    )

    assert enriched.loc[0, "BankName"] == "ING"
    assert enriched.loc[0, "AccountName"] == "Countdown"
    assert enriched.loc[0, "Extract_Date"] == "20260422"


def test_sort_qif_files_orders_by_extract_date_then_name():
    files = [
        Path("ING_Countdown_Transactions_20260422.qif"),
        Path("Adelaide_Offset_Transactions_20260419.qif"),
        Path("Adelaide_Homeloan_Transactions_20260419.qif"),
    ]

    ordered = sort_qif_files(files)

    assert [path.name for path in ordered] == [
        "Adelaide_Homeloan_Transactions_20260419.qif",
        "Adelaide_Offset_Transactions_20260419.qif",
        "ING_Countdown_Transactions_20260422.qif",
    ]


def test_union_unique_prefers_latest_extract_for_duplicate_primary_key():
    earlier = pd.DataFrame(
        {
            "primary_key": ["dup", "older-only"],
            "Extract_Date": ["20260420", "20260420"],
            "memo": ["stale", "still here"],
        }
    )
    later = pd.DataFrame(
        {
            "primary_key": ["dup", "new-only"],
            "Extract_Date": ["20260422", "20260422"],
            "memo": ["fresh", "new row"],
        }
    )

    merged = union_unique(earlier, later, "primary_key")
    merged_by_key = merged.set_index("primary_key")

    assert list(merged["primary_key"]) == ["older-only", "dup", "new-only"]
    assert merged_by_key.loc["dup", "Extract_Date"] == "20260422"
    assert merged_by_key.loc["dup", "memo"] == "fresh"


def test_assert_unique_primary_keys_raises_helpful_error():
    dataframe = pd.DataFrame(
        {
            "primary_key": ["dup", "dup", "unique"],
            "Extract_Date": ["20260422", "20260422", "20260422"],
        }
    )

    with pytest.raises(ValueError, match=r"Duplicate primary keys detected for ING/Countdown") as exc:
        assert_unique_primary_keys(
            dataframe,
            "primary_key",
            bank_name="ING",
            account_name="Countdown",
        )

    assert "sample keys: dup" in str(exc.value)
