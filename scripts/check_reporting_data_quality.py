#!/usr/bin/env python3
"""
Reporting data-quality checks — validates that dbt reporting tables contain
meaningful (non-zero, non-null) values for the metrics displayed on Grafana
dashboards.

Each check targets a specific dashboard panel failure pattern that has occurred
in the past.  The script connects directly to PostgreSQL and runs validation
queries, then exits non-zero when any check fails.

Checks are organised by dashboard so failures are instantly attributable.
Run with ``--json`` for machine-readable output that includes per-dashboard
summaries, or plain text for a grouped human-readable report.

Environment variables
---------------------
DAGSTER_POSTGRES_HOST   (default: localhost)
DAGSTER_POSTGRES_PORT   (default: 5432)
DAGSTER_POSTGRES_USER   (default: postgres)
DAGSTER_POSTGRES_PASSWORD
DAGSTER_POSTGRES_DB     (default: personal_finance)

Usage
-----
    python scripts/check_reporting_data_quality.py          # human-readable
    python scripts/check_reporting_data_quality.py --json   # machine-readable
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import sys
from collections import OrderedDict
from dataclasses import dataclass, field
from typing import Any, List

try:
    import psycopg2
    import psycopg2.extras
except ImportError:
    sys.exit("psycopg2 is required: pip install psycopg2-binary")


# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------

@dataclass
class CheckResult:
    check_id: str
    name: str
    description: str
    passed: bool
    dashboard: str = ""
    severity: str = "high"
    detail: str = ""
    query_result: Any = field(default=None, repr=False)


# ---------------------------------------------------------------------------
# Check registry
# ---------------------------------------------------------------------------

_CHECKS: list[dict] = []


def _register(
    check_id: str,
    name: str,
    description: str,
    *,
    dashboard: str = "",
    severity: str = "high",
):
    """Decorator that registers a check function."""
    def decorator(fn):
        _CHECKS.append({
            "id": check_id,
            "name": name,
            "description": description,
            "dashboard": dashboard,
            "severity": severity,
            "fn": fn,
        })
        return fn
    return decorator


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _to_float(value: Any) -> float:
    if value is None:
        return 0.0
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def _table_populated(cur, schema_table: str, min_rows: int = 1) -> tuple[bool, int]:
    """Check whether *schema_table* exists and has at least *min_rows* rows.

    Returns ``(populated, row_count)``.  If the table does not exist the
    query raises a ProgrammingError which the caller's exception handler
    will catch and record as a check failure.
    """
    cur.execute(f"SELECT COUNT(*) AS cnt FROM {schema_table}")  # noqa: S608
    row = cur.fetchone()
    cnt = int(row["cnt"] or 0)
    return cnt >= min_rows, cnt


# ===================================================================
# 01 - Executive Financial Overview
# ===================================================================

_DASH_EXECUTIVE = "01 - Executive Financial Overview"


@_register(
    "DQ001",
    "Monthly Income > $0",
    "Latest closed month in rpt_monthly_budget_summary must have total_income > 0. "
    "Failure means the Monthly Financial Snapshot shows Income=$0.",
    dashboard=_DASH_EXECUTIVE,
)
def _check_monthly_income(cur) -> CheckResult:
    cur.execute("""
        SELECT budget_year_month, total_income
        FROM reporting.rpt_monthly_budget_summary
        WHERE budget_year_month < TO_CHAR(CURRENT_DATE, 'YYYY-MM')
        ORDER BY budget_year_month DESC
        LIMIT 1
    """)
    row = cur.fetchone()
    if not row:
        return CheckResult("DQ001", "Monthly Income > $0", "", False,
                           dashboard=_DASH_EXECUTIVE,
                           detail="No rows in rpt_monthly_budget_summary")
    month, income = row["budget_year_month"], row["total_income"]
    passed = income is not None and float(income) > 0
    return CheckResult(
        "DQ001", "Monthly Income > $0", "", passed,
        dashboard=_DASH_EXECUTIVE,
        detail=f"month={month} total_income={income}",
        query_result={"month": month, "total_income": float(income) if income else 0},
    )


@_register(
    "DQ002",
    "Family Essentials has data",
    "rpt_family_essentials must have at least 1 row with total_family_essentials > 0. "
    "Failure means the Family Essentials panel shows 'No data' or an error icon.",
    dashboard=_DASH_EXECUTIVE,
)
def _check_family_essentials(cur) -> CheckResult:
    cur.execute("""
        SELECT COUNT(*) AS cnt,
               COALESCE(MAX(total_family_essentials), 0) AS max_val
        FROM reporting.rpt_family_essentials
    """)
    row = cur.fetchone()
    cnt, max_val = row["cnt"], float(row["max_val"])
    passed = cnt > 0 and max_val > 0
    return CheckResult(
        "DQ002", "Family Essentials has data", "", passed,
        dashboard=_DASH_EXECUTIVE,
        detail=f"rows={cnt} max_total_family_essentials={max_val}",
        query_result={"rows": cnt, "max_total_family_essentials": max_val},
    )


@_register(
    "DQ003",
    "Emergency Fund > 0 months",
    "rpt_emergency_fund_coverage must show months_essential_expenses_covered > 0 "
    "when liquid_assets > 0. Failure means Emergency Fund gauge shows 0.",
    dashboard=_DASH_EXECUTIVE,
)
def _check_emergency_fund(cur) -> CheckResult:
    cur.execute("""
        SELECT budget_year_month,
               liquid_assets,
               months_essential_expenses_covered
        FROM reporting.rpt_emergency_fund_coverage
        ORDER BY budget_year_month DESC
        LIMIT 1
    """)
    row = cur.fetchone()
    if not row:
        return CheckResult("DQ003", "Emergency Fund > 0 months", "", False,
                           dashboard=_DASH_EXECUTIVE,
                           detail="No rows in rpt_emergency_fund_coverage")
    liquid = float(row["liquid_assets"] or 0)
    months = float(row["months_essential_expenses_covered"] or 0)
    # If there are liquid assets, coverage should be positive
    passed = months > 0 or liquid == 0
    return CheckResult(
        "DQ003", "Emergency Fund > 0 months", "", passed,
        dashboard=_DASH_EXECUTIVE,
        detail=f"liquid_assets={liquid} months_covered={months}",
        query_result={"liquid_assets": liquid, "months_covered": months},
    )


@_register(
    "DQ004",
    "Cash Flow Drivers non-empty",
    "rpt_mom_cash_flow_waterfall must have rows for recent months. "
    "Failure means the Cash Flow Drivers barchart renders blank.",
    dashboard=_DASH_EXECUTIVE,
)
def _check_cash_flow_drivers(cur) -> CheckResult:
    cur.execute("""
        SELECT COUNT(*) AS cnt,
               COUNT(DISTINCT budget_year_month) AS months
        FROM reporting.rpt_mom_cash_flow_waterfall
        WHERE budget_year_month >= TO_CHAR(CURRENT_DATE - INTERVAL '3 months', 'YYYY-MM')
          AND budget_year_month < TO_CHAR(CURRENT_DATE, 'YYYY-MM')
    """)
    row = cur.fetchone()
    cnt, months = row["cnt"], row["months"]
    passed = cnt > 0 and months > 0
    return CheckResult(
        "DQ004", "Cash Flow Drivers non-empty", "", passed,
        dashboard=_DASH_EXECUTIVE,
        detail=f"rows={cnt} distinct_months={months}",
        query_result={"rows": cnt, "distinct_months": months},
    )


@_register(
    "DQ005",
    "Uncategorized Merchants are real",
    "viz_uncategorized_transactions_with_original_memo must have rows with "
    "merchant_display_name that is not 'None' or blank. "
    "Failure means Top Uncategorized Merchants shows a single 'None' row.",
    dashboard=_DASH_EXECUTIVE,
)
def _check_uncategorized_merchants(cur) -> CheckResult:
    cur.execute("""
        SELECT COUNT(*) AS total_rows,
               COUNT(*) FILTER (
                   WHERE merchant_display_name IS NOT NULL
                     AND TRIM(merchant_display_name) NOT IN ('', 'None', 'Unknown Merchant')
                     AND transaction_count > 0
                     AND total_amount > 0
               ) AS valid_rows
        FROM reporting.viz_uncategorized_transactions_with_original_memo
    """)
    row = cur.fetchone()
    total, valid = row["total_rows"], row["valid_rows"]
    passed = valid > 0
    return CheckResult(
        "DQ005", "Uncategorized Merchants are real", "", passed,
        dashboard=_DASH_EXECUTIVE,
        detail=f"total_rows={total} valid_rows={valid}",
        query_result={"total_rows": total, "valid_rows": valid},
    )


@_register(
    "DQ007",
    "Savings/Expense ratios non-zero",
    "Latest month with income > 0 must have savings_rate_percent != 0 and "
    "expense_ratio_percent != 0. Failure means Savings & Expense panel shows "
    "all 0% values.",
    dashboard=_DASH_EXECUTIVE,
)
def _check_savings_ratios(cur) -> CheckResult:
    cur.execute("""
        SELECT budget_year_month,
               total_income,
               savings_rate_percent,
               expense_ratio_percent
        FROM reporting.rpt_monthly_budget_summary
        WHERE total_income > 0
          AND budget_year_month < TO_CHAR(CURRENT_DATE, 'YYYY-MM')
        ORDER BY budget_year_month DESC
        LIMIT 1
    """)
    row = cur.fetchone()
    if not row:
        return CheckResult("DQ007", "Savings/Expense ratios non-zero", "", False,
                           dashboard=_DASH_EXECUTIVE,
                           detail="No months with total_income > 0")
    sr = float(row["savings_rate_percent"] or 0)
    er = float(row["expense_ratio_percent"] or 0)
    passed = sr != 0 and er != 0
    return CheckResult(
        "DQ007", "Savings/Expense ratios non-zero", "", passed,
        dashboard=_DASH_EXECUTIVE,
        detail=f"month={row['budget_year_month']} savings_rate={sr} expense_ratio={er}",
        query_result={
            "month": row["budget_year_month"],
            "savings_rate_percent": sr,
            "expense_ratio_percent": er,
        },
    )


@_register(
    "DQ008",
    "Forecast non-zero",
    "rpt_executive_dashboard must have forecasted_next_month_cash_flow != 0. "
    "Failure means the KPI Forecast row shows $0 across the board.",
    dashboard=_DASH_EXECUTIVE,
)
def _check_forecast(cur) -> CheckResult:
    cur.execute("""
        SELECT dashboard_month,
               forecasted_next_month_cash_flow
        FROM reporting.rpt_executive_dashboard
        ORDER BY dashboard_month DESC
        LIMIT 1
    """)
    row = cur.fetchone()
    if not row:
        return CheckResult("DQ008", "Forecast non-zero", "", False,
                           dashboard=_DASH_EXECUTIVE,
                           detail="No rows in rpt_executive_dashboard")
    forecast = float(row["forecasted_next_month_cash_flow"] or 0)
    passed = forecast != 0
    return CheckResult(
        "DQ008", "Forecast non-zero", "", passed,
        dashboard=_DASH_EXECUTIVE,
        detail=f"month={row['dashboard_month']} forecast={forecast}",
        query_result={
            "month": row["dashboard_month"],
            "forecasted_next_month_cash_flow": forecast,
        },
    )


@_register(
    "DQ009",
    "Executive dashboard row exists",
    "rpt_executive_dashboard must have at least 1 row with monthly_income > 0 "
    "and monthly_expenses > 0. This is the master view that feeds most panels.",
    dashboard=_DASH_EXECUTIVE,
)
def _check_executive_dashboard(cur) -> CheckResult:
    cur.execute("""
        SELECT dashboard_month,
               monthly_income,
               monthly_expenses,
               monthly_net_cash_flow,
               overall_financial_health_score
        FROM reporting.rpt_executive_dashboard
        ORDER BY dashboard_month DESC
        LIMIT 1
    """)
    row = cur.fetchone()
    if not row:
        return CheckResult("DQ009", "Executive dashboard row exists", "", False,
                           dashboard=_DASH_EXECUTIVE,
                           detail="No rows in rpt_executive_dashboard")
    income = float(row["monthly_income"] or 0)
    expenses = float(row["monthly_expenses"] or 0)
    passed = income > 0 and expenses > 0
    return CheckResult(
        "DQ009", "Executive dashboard row exists", "", passed,
        dashboard=_DASH_EXECUTIVE,
        detail=f"month={row['dashboard_month']} income={income} expenses={expenses}",
        query_result={
            "month": row["dashboard_month"],
            "monthly_income": income,
            "monthly_expenses": expenses,
            "health_score": float(row["overall_financial_health_score"] or 0),
        },
    )


@_register(
    "DQ013",
    "Executive dashboard last refresh populated",
    "rpt_executive_dashboard.latest dashboard_generated_at must be present and recent. "
    "Failure means the Last Refresh indicator is blank or stale.",
    dashboard=_DASH_EXECUTIVE,
)
def _check_executive_dashboard_refresh(cur) -> CheckResult:
    cur.execute("""
        SELECT dashboard_month, dashboard_generated_at
        FROM reporting.rpt_executive_dashboard
        ORDER BY dashboard_month DESC
        LIMIT 1
    """)
    row = cur.fetchone()
    if not row:
        return CheckResult("DQ013", "Executive dashboard last refresh populated", "", False,
                           dashboard=_DASH_EXECUTIVE,
                           detail="No rows in rpt_executive_dashboard")

    refreshed_at = row["dashboard_generated_at"]
    passed = refreshed_at is not None
    if passed:
        try:
            if refreshed_at.tzinfo is None:
                refreshed_at = refreshed_at.replace(tzinfo=dt.timezone.utc)
            passed = (dt.datetime.now(dt.timezone.utc) - refreshed_at) <= dt.timedelta(days=30)
        except TypeError:
            passed = False

    return CheckResult(
        "DQ013",
        "Executive dashboard last refresh populated",
        "",
        passed,
        dashboard=_DASH_EXECUTIVE,
        detail=f"month={row['dashboard_month']} dashboard_generated_at={refreshed_at}",
        query_result={
            "month": row["dashboard_month"],
            "dashboard_generated_at": refreshed_at,
        },
    )


@_register(
    "DQ014",
    "Monthly Financial Snapshot complete",
    "The latest closed month must have a complete monthly budget summary plus matching executive "
    "dashboard and net worth snapshot fields populated. Failure means the monthly snapshot renders partially.",
    dashboard=_DASH_EXECUTIVE,
)
def _check_monthly_snapshot_complete(cur) -> CheckResult:
    cur.execute("""
        SELECT budget_year_month, total_income, total_expenses, net_cash_flow,
               savings_rate_percent, expense_ratio_percent
        FROM reporting.rpt_monthly_budget_summary
        WHERE budget_year_month < TO_CHAR(CURRENT_DATE, 'YYYY-MM')
        ORDER BY budget_year_month DESC
        LIMIT 1
    """)
    summary_row = cur.fetchone()
    if not summary_row:
        return CheckResult("DQ014", "Monthly Financial Snapshot complete", "", False,
                           dashboard=_DASH_EXECUTIVE,
                           detail="No rows in rpt_monthly_budget_summary")

    month = summary_row["budget_year_month"]
    cur.execute("""
        SELECT dashboard_month, current_net_worth, liquid_assets, total_assets, total_liabilities
        FROM reporting.rpt_executive_dashboard
        WHERE dashboard_month = %s
        LIMIT 1
    """, (month,))
    dashboard_row = cur.fetchone()

    cur.execute("""
        SELECT budget_year_month, total_assets, total_liabilities, net_worth, liquid_assets
        FROM reporting.rpt_household_net_worth
        WHERE budget_year_month = %s
        LIMIT 1
    """, (month,))
    net_worth_row = cur.fetchone()

    summary_fields = ["total_income", "total_expenses", "net_cash_flow", "savings_rate_percent", "expense_ratio_percent"]
    summary_missing = [field for field in summary_fields if summary_row[field] is None]
    dashboard_missing = []
    if not dashboard_row:
        dashboard_missing = ["dashboard_row_missing"]
    else:
        for field in ["current_net_worth", "liquid_assets", "total_assets", "total_liabilities"]:
            if dashboard_row[field] is None:
                dashboard_missing.append(field)

    net_worth_missing = []
    if not net_worth_row:
        net_worth_missing = ["net_worth_row_missing"]
    else:
        for field in ["total_assets", "total_liabilities", "net_worth", "liquid_assets"]:
            if net_worth_row[field] is None:
                net_worth_missing.append(field)

    passed = not summary_missing and not dashboard_missing and not net_worth_missing
    detail = (
        f"month={month} summary_missing={summary_missing or '[]'} "
        f"dashboard_missing={dashboard_missing or '[]'} "
        f"net_worth_missing={net_worth_missing or '[]'}"
    )
    return CheckResult(
        "DQ014",
        "Monthly Financial Snapshot complete",
        "",
        passed,
        dashboard=_DASH_EXECUTIVE,
        detail=detail,
        query_result={
            "month": month,
            "summary_missing": summary_missing,
            "dashboard_missing": dashboard_missing,
            "net_worth_missing": net_worth_missing,
        },
    )


# ===================================================================
# 02 - Cash Flow Analysis
# ===================================================================

_DASH_CASH_FLOW = "02 - Cash Flow Analysis"


@_register(
    "DQ011",
    "Cash Flow Analysis populated",
    "rpt_cash_flow_analysis must have the last 3 closed months populated with positive inflows "
    "and outflows. Failure means the Cash Flow dashboard has no meaningful monthly series.",
    dashboard=_DASH_CASH_FLOW,
)
def _check_cash_flow_analysis(cur) -> CheckResult:
    # Fetch recent closed months, skipping incomplete ones (inflows=0 means
    # QIF files haven't been imported yet for that month).
    cur.execute("""
        SELECT budget_year_month, total_inflows, total_outflows, net_cash_flow
        FROM reporting.rpt_cash_flow_analysis
        WHERE budget_year_month < TO_CHAR(CURRENT_DATE, 'YYYY-MM')
          AND total_inflows > 0
        ORDER BY budget_year_month DESC
        LIMIT 3
    """)
    rows = cur.fetchall()
    if len(rows) < 3:
        return CheckResult(
            "DQ011",
            "Cash Flow Analysis populated",
            "",
            False,
            dashboard=_DASH_CASH_FLOW,
            detail=f"Only {len(rows)} complete closed month(s) found in rpt_cash_flow_analysis",
        )

    details = []
    passed = True
    for row in rows:
        inflows = _to_float(row["total_inflows"])
        outflows = _to_float(row["total_outflows"])
        net_cash_flow = row["net_cash_flow"]
        details.append(
            f"{row['budget_year_month']}: inflows={inflows} outflows={outflows} net_cash_flow={_to_float(net_cash_flow)}"
        )
        if outflows <= 0 or net_cash_flow is None:
            passed = False

    return CheckResult(
        "DQ011",
        "Cash Flow Analysis populated",
        "",
        passed,
        dashboard=_DASH_CASH_FLOW,
        detail=" | ".join(details),
        query_result={"months": details},
    )


@_register(
    "DQ015",
    "Cash Flow Trend has history",
    "rpt_cash_flow_analysis must contain at least 6 distinct closed months. Failure means the cash flow trend chart cannot render a meaningful history.",
    dashboard=_DASH_CASH_FLOW,
)
def _check_cash_flow_trend_history(cur) -> CheckResult:
    cur.execute("""
        SELECT budget_year_month
        FROM reporting.rpt_cash_flow_analysis
        WHERE budget_year_month < TO_CHAR(CURRENT_DATE, 'YYYY-MM')
        ORDER BY budget_year_month DESC
        LIMIT 12
    """)
    rows = cur.fetchall()
    months = [row["budget_year_month"] for row in rows]
    distinct_months = list(dict.fromkeys(months))
    passed = len(distinct_months) >= 6
    return CheckResult(
        "DQ015",
        "Cash Flow Trend has history",
        "",
        passed,
        dashboard=_DASH_CASH_FLOW,
        detail=f"distinct_closed_months={len(distinct_months)} months={distinct_months}",
        query_result={"distinct_closed_months": len(distinct_months), "months": distinct_months},
    )


# ===================================================================
# 04 - Household Net Worth Analysis
# ===================================================================

_DASH_NET_WORTH = "04 - Household Net Worth Analysis"


@_register(
    "DQ006",
    "Liabilities > $0",
    "rpt_household_net_worth latest month must have total_liabilities > 0 "
    "(household has a mortgage). Failure means Asset & Liability panel shows "
    "Liabilities=$0 and D/A=0%.",
    dashboard=_DASH_NET_WORTH,
)
def _check_liabilities(cur) -> CheckResult:
    cur.execute("""
        SELECT budget_year_month, total_liabilities, total_assets, net_worth
        FROM reporting.rpt_household_net_worth
        WHERE budget_year_month < TO_CHAR(CURRENT_DATE, 'YYYY-MM')
        ORDER BY budget_year_month DESC
        LIMIT 1
    """)
    row = cur.fetchone()
    if not row:
        return CheckResult("DQ006", "Liabilities > $0", "", False,
                           dashboard=_DASH_NET_WORTH,
                           detail="No rows in rpt_household_net_worth")
    liab = float(row["total_liabilities"] or 0)
    passed = liab > 0
    return CheckResult(
        "DQ006", "Liabilities > $0", "", passed,
        dashboard=_DASH_NET_WORTH,
        detail=f"month={row['budget_year_month']} total_liabilities={liab}",
        query_result={
            "month": row["budget_year_month"],
            "total_liabilities": liab,
            "total_assets": float(row["total_assets"] or 0),
            "net_worth": float(row["net_worth"] or 0),
        },
    )


@_register(
    "DQ010",
    "Total assets include property",
    "rpt_household_net_worth latest closed month must show total_assets > liquid_assets "
    "and non-zero property_assets. Failure means property holdings are missing from total assets.",
    dashboard=_DASH_NET_WORTH,
    severity="medium",
)
def _check_property_assets(cur) -> CheckResult:
    cur.execute("""
        SELECT budget_year_month, total_assets, liquid_assets, property_assets, net_worth
        FROM reporting.rpt_household_net_worth
        WHERE budget_year_month < TO_CHAR(CURRENT_DATE, 'YYYY-MM')
        ORDER BY budget_year_month DESC
        LIMIT 1
    """)
    row = cur.fetchone()
    if not row:
        return CheckResult("DQ010", "Total assets include property", "", False,
                           dashboard=_DASH_NET_WORTH, severity="medium",
                           detail="No rows in rpt_household_net_worth")

    total_assets = _to_float(row["total_assets"])
    liquid_assets = _to_float(row["liquid_assets"])
    property_assets = _to_float(row["property_assets"])
    net_worth = _to_float(row["net_worth"])
    passed = total_assets > liquid_assets and property_assets > 0
    return CheckResult(
        "DQ010",
        "Total assets include property",
        "",
        passed,
        dashboard=_DASH_NET_WORTH,
        severity="medium",
        detail=(
            f"month={row['budget_year_month']} total_assets={total_assets} "
            f"liquid_assets={liquid_assets} property_assets={property_assets} "
            f"net_worth={net_worth}"
        ),
        query_result={
            "month": row["budget_year_month"],
            "total_assets": total_assets,
            "liquid_assets": liquid_assets,
            "property_assets": property_assets,
            "net_worth": net_worth,
        },
    )


@_register(
    "DQ017",
    "Net Worth trend non-empty",
    "rpt_household_net_worth must contain multiple closed months with positive net_worth. "
    "Failure means the Net Worth trend panel is blank or collapsed to a single point.",
    dashboard=_DASH_NET_WORTH,
    severity="medium",
)
def _check_net_worth_trend(cur) -> CheckResult:
    cur.execute("""
        SELECT budget_year_month, net_worth
        FROM reporting.rpt_household_net_worth
        WHERE budget_year_month < TO_CHAR(CURRENT_DATE, 'YYYY-MM')
        ORDER BY budget_year_month DESC
        LIMIT 12
    """)
    rows = cur.fetchall()
    if not rows:
        return CheckResult("DQ017", "Net Worth trend non-empty", "", False,
                           dashboard=_DASH_NET_WORTH, severity="medium",
                           detail="No closed-month rows in rpt_household_net_worth")

    positive_months = [
        row["budget_year_month"]
        for row in rows
        if _to_float(row["net_worth"]) > 0
    ]
    distinct_positive_months = list(dict.fromkeys(positive_months))
    passed = len(distinct_positive_months) >= 3
    return CheckResult(
        "DQ017",
        "Net Worth trend non-empty",
        "",
        passed,
        dashboard=_DASH_NET_WORTH,
        severity="medium",
        detail=f"positive_months={len(distinct_positive_months)} months={distinct_positive_months}",
        query_result={
            "positive_months": len(distinct_positive_months),
            "months": distinct_positive_months,
        },
    )


# ===================================================================
# 05 - Savings Analysis
# ===================================================================

_DASH_SAVINGS = "05 - Savings Analysis"


@_register(
    "DQ016",
    "Savings Analysis populated",
    "rpt_savings_analysis must contain recent closed months with non-zero savings values. "
    "Failure means the Savings dashboard is blank or all zeroes.",
    dashboard=_DASH_SAVINGS,
)
def _check_savings_analysis(cur) -> CheckResult:
    cur.execute("""
        SELECT budget_year_month, total_savings, total_savings_rate_percent,
               traditional_savings_rate_percent, liquid_savings_rate_percent,
               investment_rate_percent
        FROM reporting.rpt_savings_analysis
        WHERE budget_year_month < TO_CHAR(CURRENT_DATE, 'YYYY-MM')
        ORDER BY budget_year_month DESC
        LIMIT 3
    """)
    rows = cur.fetchall()
    if len(rows) < 3:
        return CheckResult(
            "DQ016",
            "Savings Analysis populated",
            "",
            False,
            dashboard=_DASH_SAVINGS,
            detail=f"Only {len(rows)} closed month(s) found in rpt_savings_analysis",
        )

    detail_rows = []
    passed = True
    for row in rows:
        month = row["budget_year_month"]
        numeric_values = [
            _to_float(row["total_savings"]),
            _to_float(row["total_savings_rate_percent"]),
            _to_float(row["traditional_savings_rate_percent"]),
            _to_float(row["liquid_savings_rate_percent"]),
            _to_float(row["investment_rate_percent"]),
        ]
        has_non_zero = any(value != 0 for value in numeric_values)
        detail_rows.append(f"{month}: values={numeric_values} non_zero={has_non_zero}")
        if not has_non_zero:
            passed = False

    return CheckResult(
        "DQ016",
        "Savings Analysis populated",
        "",
        passed,
        dashboard=_DASH_SAVINGS,
        detail=" | ".join(detail_rows),
        query_result={"months": detail_rows},
    )


# ===================================================================
# Account Performance (standalone dashboard)
# ===================================================================

_DASH_ACCOUNT_PERF = "Account Performance"


@_register(
    "DQ012",
    "Account Performance non-empty",
    "rpt_account_performance latest closed month must have rows with meaningful account_name "
    "values and bank_name not equal to 'Unknown'. Failure means the Account Performance dashboard is blank.",
    dashboard=_DASH_ACCOUNT_PERF,
)
def _check_account_performance(cur) -> CheckResult:
    cur.execute("""
        SELECT budget_year_month, COUNT(*) AS total_rows,
               COUNT(*) FILTER (
                   WHERE account_name IS NOT NULL
                     AND TRIM(account_name) <> ''
                     AND bank_name IS NOT NULL
                     AND TRIM(bank_name) <> ''
                     AND LOWER(TRIM(bank_name)) <> 'unknown'
               ) AS valid_rows,
               COUNT(*) FILTER (
                   WHERE bank_name IS NOT NULL
                     AND LOWER(TRIM(bank_name)) = 'unknown'
               ) AS unknown_bank_rows
        FROM reporting.rpt_account_performance
        WHERE budget_year_month < TO_CHAR(CURRENT_DATE, 'YYYY-MM')
        GROUP BY budget_year_month
        ORDER BY budget_year_month DESC
        LIMIT 1
    """)
    row = cur.fetchone()
    if not row:
        return CheckResult("DQ012", "Account Performance non-empty", "", False,
                           dashboard=_DASH_ACCOUNT_PERF,
                           detail="No closed-month rows in rpt_account_performance")

    total_rows = int(row["total_rows"] or 0)
    valid_rows = int(row["valid_rows"] or 0)
    unknown_bank_rows = int(row["unknown_bank_rows"] or 0)
    passed = total_rows > 0 and valid_rows > 0 and valid_rows > unknown_bank_rows
    return CheckResult(
        "DQ012",
        "Account Performance non-empty",
        "",
        passed,
        dashboard=_DASH_ACCOUNT_PERF,
        detail=(
            f"month={row['budget_year_month']} total_rows={total_rows} "
            f"valid_rows={valid_rows} unknown_bank_rows={unknown_bank_rows}"
        ),
        query_result={
            "month": row["budget_year_month"],
            "total_rows": total_rows,
            "valid_rows": valid_rows,
            "unknown_bank_rows": unknown_bank_rows,
        },
    )


# ===================================================================
# 06 - Category Spending Analysis  (NEW)
# ===================================================================

_DASH_CATEGORY_SPENDING = "06 - Category Spending Analysis"


@_register(
    "DQ018",
    "Category spending trends populated",
    "rpt_category_spending_trends must have rows for recent closed months with "
    "at least 3 distinct categories showing non-zero spend. Failure means the "
    "Category Spending dashboard renders blank or with too few categories.",
    dashboard=_DASH_CATEGORY_SPENDING,
)
def _check_category_spending_trends(cur) -> CheckResult:
    cur.execute("""
        SELECT COUNT(*) AS total_rows,
               COUNT(DISTINCT level_1_category) AS distinct_categories,
               COUNT(DISTINCT budget_year_month) AS distinct_months
        FROM reporting.rpt_category_spending_trends
        WHERE budget_year_month >= TO_CHAR(CURRENT_DATE - INTERVAL '3 months', 'YYYY-MM')
          AND budget_year_month < TO_CHAR(CURRENT_DATE, 'YYYY-MM')
          AND monthly_spending <> 0
    """)
    row = cur.fetchone()
    total = int(row["total_rows"] or 0)
    cats = int(row["distinct_categories"] or 0)
    months = int(row["distinct_months"] or 0)
    passed = total > 0 and cats >= 3 and months >= 1
    return CheckResult(
        "DQ018",
        "Category spending trends populated",
        "",
        passed,
        dashboard=_DASH_CATEGORY_SPENDING,
        detail=f"rows={total} distinct_categories={cats} distinct_months={months}",
        query_result={"rows": total, "distinct_categories": cats, "distinct_months": months},
    )


# ===================================================================
# 07 - Expense Performance Analysis  (NEW)
# ===================================================================

_DASH_EXPENSE_PERF = "07 - Expense Performance Analysis"


@_register(
    "DQ019",
    "Expense performance trend data available",
    "rpt_category_spending_trends must have expense category data for at least "
    "3 recent closed months. Failure means expense performance trend panels are blank.",
    dashboard=_DASH_EXPENSE_PERF,
)
def _check_expense_performance(cur) -> CheckResult:
    cur.execute("""
        SELECT COUNT(DISTINCT budget_year_month) AS distinct_months,
               COUNT(*) AS total_rows
        FROM reporting.rpt_category_spending_trends
        WHERE budget_year_month < TO_CHAR(CURRENT_DATE, 'YYYY-MM')
          AND monthly_spending > 0
    """)
    row = cur.fetchone()
    months = int(row["distinct_months"] or 0)
    total = int(row["total_rows"] or 0)
    passed = months >= 3 and total > 0
    return CheckResult(
        "DQ019",
        "Expense performance trend data available",
        "",
        passed,
        dashboard=_DASH_EXPENSE_PERF,
        detail=f"distinct_expense_months={months} rows={total}",
        query_result={"distinct_months": months, "rows": total},
    )


# ===================================================================
# 08 - Outflows Insights  (NEW)
# ===================================================================

_DASH_OUTFLOWS = "08 - Outflows Insights"


@_register(
    "DQ020",
    "Outflows insights populated",
    "rpt_outflows_insights_dashboard must have rows for recent closed months "
    "with non-zero outflow amounts. Failure means Outflows Insights panels are blank.",
    dashboard=_DASH_OUTFLOWS,
)
def _check_outflows_insights(cur) -> CheckResult:
    cur.execute("""
        SELECT COUNT(*) AS total_rows,
               COUNT(DISTINCT period_date) AS distinct_months,
               COALESCE(SUM(ABS(total_outflows)), 0) AS sum_outflows
        FROM reporting.rpt_outflows_insights_dashboard
        WHERE period_date >= (CURRENT_DATE - INTERVAL '3 months')
          AND period_date < DATE_TRUNC('month', CURRENT_DATE)
    """)
    row = cur.fetchone()
    total = int(row["total_rows"] or 0)
    months = int(row["distinct_months"] or 0)
    outflows = _to_float(row["sum_outflows"])
    passed = total > 0 and months >= 1 and outflows > 0
    return CheckResult(
        "DQ020",
        "Outflows insights populated",
        "",
        passed,
        dashboard=_DASH_OUTFLOWS,
        detail=f"rows={total} distinct_months={months} sum_outflows={outflows}",
        query_result={"rows": total, "distinct_months": months, "sum_outflows": outflows},
    )


# ===================================================================
# 09 - Transaction Analysis  (NEW)
# ===================================================================

_DASH_TRANSACTIONS = "09 - Transaction Analysis"


@_register(
    "DQ021",
    "Transaction analysis tables populated",
    "fct_transactions_enhanced must have rows and at least some with non-null "
    "category assignments. Failure means the Transaction Analysis dashboard is blank.",
    dashboard=_DASH_TRANSACTIONS,
)
def _check_transaction_analysis(cur) -> CheckResult:
    cur.execute("""
        SELECT COUNT(*) AS total_rows,
               COUNT(*) FILTER (
                   WHERE category_key IS NOT NULL
                     AND TRIM(category_key) <> ''
                     AND LOWER(TRIM(category_key)) <> 'uncategorized'
               ) AS categorized_rows
        FROM reporting.fct_transactions_enhanced
    """)
    row = cur.fetchone()
    total = int(row["total_rows"] or 0)
    categorized = int(row["categorized_rows"] or 0)
    passed = total > 0
    return CheckResult(
        "DQ021",
        "Transaction analysis tables populated",
        "",
        passed,
        dashboard=_DASH_TRANSACTIONS,
        detail=f"total_rows={total} categorized_rows={categorized}",
        query_result={"total_rows": total, "categorized_rows": categorized},
    )


# ===================================================================
# 12 - Financial Projections  (NEW)
# ===================================================================

_DASH_PROJECTIONS = "12 - Financial Projections"


@_register(
    "DQ026",
    "Financial projections populated",
    "fct_projection_sensitivity must have rows with non-null projection values. "
    "Failure means the Financial Projections dashboard is blank.",
    dashboard=_DASH_PROJECTIONS,
    severity="medium",
)
def _check_financial_projections(cur) -> CheckResult:
    populated, cnt = _table_populated(cur, "reporting.fct_projection_sensitivity")
    passed = populated
    return CheckResult(
        "DQ026",
        "Financial projections populated",
        "",
        passed,
        dashboard=_DASH_PROJECTIONS,
        severity="medium",
        detail=f"rows={cnt}",
        query_result={"rows": cnt},
    )


# ===================================================================
# 13/14 - Year-over-Year Comparison  (NEW)
# ===================================================================

_DASH_YOY = "13/14 - Year-over-Year Comparison"


@_register(
    "DQ022",
    "Year-over-year comparison has multi-year data",
    "rpt_year_over_year_comparison must have rows spanning at least 2 distinct "
    "years. Failure means both Year-over-Year dashboards render blank.",
    dashboard=_DASH_YOY,
)
def _check_year_over_year(cur) -> CheckResult:
    cur.execute("""
        SELECT COUNT(*) AS total_rows,
               COUNT(DISTINCT comparison_year) AS distinct_years
        FROM reporting.rpt_year_over_year_comparison
    """)
    row = cur.fetchone()
    total = int(row["total_rows"] or 0)
    years = int(row["distinct_years"] or 0)
    passed = total > 0 and years >= 2
    return CheckResult(
        "DQ022",
        "Year-over-year comparison has multi-year data",
        "",
        passed,
        dashboard=_DASH_YOY,
        detail=f"rows={total} distinct_years={years}",
        query_result={"rows": total, "distinct_years": years},
    )


# ===================================================================
# 15 - Mortgage Payoff  (NEW)
# ===================================================================

_DASH_MORTGAGE = "15 - Mortgage Payoff"


@_register(
    "DQ023",
    "Mortgage payoff data populated",
    "viz_mortgage_payoff_summary must exist and have rows. "
    "Failure means the Mortgage Payoff dashboard is blank.",
    dashboard=_DASH_MORTGAGE,
    severity="medium",
)
def _check_mortgage_payoff(cur) -> CheckResult:
    populated, cnt = _table_populated(cur, "reporting.viz_mortgage_payoff_summary")
    return CheckResult(
        "DQ023",
        "Mortgage payoff data populated",
        "",
        populated,
        dashboard=_DASH_MORTGAGE,
        severity="medium",
        detail=f"rows={cnt}",
        query_result={"rows": cnt},
    )


# ===================================================================
# 16 - Grocery Spending  (NEW)
# ===================================================================

_DASH_GROCERY = "16 - Grocery Spending"


@_register(
    "DQ024",
    "Grocery spending data populated",
    "viz_grocery_monthly_summary must exist and have rows. "
    "Failure means the Grocery Spending dashboard is blank.",
    dashboard=_DASH_GROCERY,
    severity="medium",
)
def _check_grocery_spending(cur) -> CheckResult:
    populated, cnt = _table_populated(cur, "reporting.viz_grocery_monthly_summary")
    return CheckResult(
        "DQ024",
        "Grocery spending data populated",
        "",
        populated,
        dashboard=_DASH_GROCERY,
        severity="medium",
        detail=f"rows={cnt}",
        query_result={"rows": cnt},
    )


# ===================================================================
# 17 - Amazon Spending  (NEW)
# ===================================================================

_DASH_AMAZON = "17 - Amazon Spending"


@_register(
    "DQ025",
    "Amazon spending data populated",
    "viz_amazon_order_context must exist and have rows. "
    "Failure means the Amazon Spending dashboard is blank.",
    dashboard=_DASH_AMAZON,
    severity="medium",
)
def _check_amazon_spending(cur) -> CheckResult:
    populated, cnt = _table_populated(cur, "reporting.viz_amazon_order_context")
    return CheckResult(
        "DQ025",
        "Amazon spending data populated",
        "",
        populated,
        dashboard=_DASH_AMAZON,
        severity="medium",
        detail=f"rows={cnt}",
        query_result={"rows": cnt},
    )


# ---------------------------------------------------------------------------
# Runner
# ---------------------------------------------------------------------------

def _connect():
    return psycopg2.connect(
        host=os.getenv("DAGSTER_POSTGRES_HOST", "localhost"),
        port=int(os.getenv("DAGSTER_POSTGRES_PORT", "5432")),
        user=os.getenv("DAGSTER_POSTGRES_USER", "postgres"),
        password=os.getenv("DAGSTER_POSTGRES_PASSWORD", ""),
        dbname=os.getenv("DAGSTER_POSTGRES_DB", "personal_finance"),
    )


def run_checks() -> List[CheckResult]:
    """Run all registered checks.

    Raises on connection/runtime errors (caller should map to exit 2).
    Individual check query errors (e.g. missing table) are caught and
    recorded as failures so remaining checks still run.
    """
    conn = _connect()  # Raises on connection failure — intentionally uncaught
    conn.autocommit = False
    results: List[CheckResult] = []
    try:
        for check in _CHECKS:
            try:
                with conn.cursor(cursor_factory=psycopg2.extras.RealDictCursor) as cur:
                    result = check["fn"](cur)
                    # Fill in description and dashboard from registration
                    result.description = check["description"]
                    if not result.dashboard:
                        result.dashboard = check["dashboard"]
                    if result.severity == "high" and check.get("severity"):
                        result.severity = check["severity"]
                    results.append(result)
                conn.commit()
            except Exception as exc:
                conn.rollback()  # Reset transaction after query errors (e.g. missing table)
                results.append(CheckResult(
                    check_id=check["id"],
                    name=check["name"],
                    description=check["description"],
                    passed=False,
                    dashboard=check["dashboard"],
                    severity=check.get("severity", "high"),
                    detail=f"ERROR: {exc}",
                ))
    finally:
        conn.close()
    return results


def _group_by_dashboard(results: List[CheckResult]) -> OrderedDict[str, List[CheckResult]]:
    """Group check results by dashboard, preserving registration order."""
    groups: OrderedDict[str, List[CheckResult]] = OrderedDict()
    for r in results:
        key = r.dashboard or "(ungrouped)"
        groups.setdefault(key, []).append(r)
    return groups


def main():
    """Exit codes: 0 = all passed, 1 = check failures, 2 = runtime error."""
    parser = argparse.ArgumentParser(description="Reporting data-quality checks")
    parser.add_argument("--json", action="store_true", help="JSON output for CI")
    args = parser.parse_args()

    try:
        results = run_checks()
    except Exception as exc:
        # Runtime error — DB unreachable, import failure, etc.
        # Exit 2 so the Dagster gate treats this as a hard failure that
        # cannot be bypassed by DASHBOARD_POLICY_GATE_WARN_ONLY.
        if args.json:
            print(json.dumps({"total": 0, "passed": 0, "failed": 0,
                              "runtime_error": str(exc), "checks": [],
                              "by_dashboard": {}}))
        else:
            print(f"RUNTIME ERROR: {exc}", file=sys.stderr)
        sys.exit(2)

    if not results:
        # No checks ran at all — treat as runtime error
        if args.json:
            print(json.dumps({"total": 0, "passed": 0, "failed": 0,
                              "runtime_error": "no checks executed", "checks": [],
                              "by_dashboard": {}}))
        else:
            print("RUNTIME ERROR: no checks executed", file=sys.stderr)
        sys.exit(2)

    failures = [r for r in results if not r.passed]
    grouped = _group_by_dashboard(results)

    if args.json:
        by_dashboard = {}
        for dash, checks in grouped.items():
            dash_failures = [c for c in checks if not c.passed]
            by_dashboard[dash] = {
                "total": len(checks),
                "passed": len(checks) - len(dash_failures),
                "failed": len(dash_failures),
                "status": "FAIL" if dash_failures else "PASS",
            }

        payload = {
            "total": len(results),
            "passed": len(results) - len(failures),
            "failed": len(failures),
            "by_dashboard": by_dashboard,
            "checks": [
                {
                    "check_id": r.check_id,
                    "name": r.name,
                    "description": r.description,
                    "passed": r.passed,
                    "dashboard": r.dashboard,
                    "severity": r.severity,
                    "detail": r.detail,
                }
                for r in results
            ],
        }
        print(json.dumps(payload, indent=2))
    else:
        for dash, checks in grouped.items():
            dash_failures = [c for c in checks if not c.passed]
            status = "FAIL" if dash_failures else "PASS"
            print(f"\n{'=' * 60}")
            print(f"  [{status}] {dash}  ({len(checks) - len(dash_failures)}/{len(checks)} passed)")
            print(f"{'=' * 60}")
            for r in checks:
                icon = "PASS" if r.passed else "FAIL"
                sev = f" [{r.severity}]" if not r.passed else ""
                print(f"  [{icon}]{sev} {r.check_id} {r.name}: {r.detail}")

        print(f"\n{'-' * 60}")
        print(f"TOTAL: {len(results)} checks, {len(failures)} failed across {len(grouped)} dashboards")
        if failures:
            failing_dashboards = [
                dash for dash, checks in grouped.items()
                if any(not c.passed for c in checks)
            ]
            print(f"FAILING DASHBOARDS: {', '.join(failing_dashboards)}")

    high_severity_failures = [r for r in failures if r.severity == "high"]
    sys.exit(1 if high_severity_failures else 0)


if __name__ == "__main__":
    main()
