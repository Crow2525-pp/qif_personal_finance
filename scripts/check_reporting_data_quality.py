#!/usr/bin/env python3
"""
Reporting data-quality checks — validates that dbt reporting tables contain
meaningful (non-zero, non-null) values for the metrics displayed on Grafana
dashboards.

Each check targets a specific dashboard panel failure pattern that has occurred
in the past.  The script connects directly to PostgreSQL and runs validation
queries, then exits non-zero when any check fails.

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
import json
import os
import sys
from dataclasses import asdict, dataclass, field
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
    detail: str = ""
    query_result: Any = field(default=None, repr=False)


# ---------------------------------------------------------------------------
# Individual checks
# ---------------------------------------------------------------------------

_CHECKS: list[dict] = []


def _register(check_id: str, name: str, description: str):
    """Decorator that registers a check function."""
    def decorator(fn):
        _CHECKS.append({"id": check_id, "name": name, "description": description, "fn": fn})
        return fn
    return decorator


@_register(
    "DQ001",
    "Monthly Income > $0",
    "Latest closed month in rpt_monthly_budget_summary must have total_income > 0. "
    "Failure means the Monthly Financial Snapshot shows Income=$0.",
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
                           "No rows in rpt_monthly_budget_summary")
    month, income = row["budget_year_month"], row["total_income"]
    passed = income is not None and float(income) > 0
    return CheckResult(
        "DQ001", "Monthly Income > $0", "", passed,
        f"month={month} total_income={income}",
        query_result={"month": month, "total_income": float(income) if income else 0},
    )


@_register(
    "DQ002",
    "Family Essentials has data",
    "rpt_family_essentials must have at least 1 row with total_family_essentials > 0. "
    "Failure means the Family Essentials panel shows 'No data' or an error icon.",
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
        f"rows={cnt} max_total_family_essentials={max_val}",
        query_result={"rows": cnt, "max_total_family_essentials": max_val},
    )


@_register(
    "DQ003",
    "Emergency Fund > 0 months",
    "rpt_emergency_fund_coverage must show months_essential_expenses_covered > 0 "
    "when liquid_assets > 0. Failure means Emergency Fund gauge shows 0.",
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
                           "No rows in rpt_emergency_fund_coverage")
    liquid = float(row["liquid_assets"] or 0)
    months = float(row["months_essential_expenses_covered"] or 0)
    # If there are liquid assets, coverage should be positive
    passed = months > 0 or liquid == 0
    return CheckResult(
        "DQ003", "Emergency Fund > 0 months", "", passed,
        f"liquid_assets={liquid} months_covered={months}",
        query_result={"liquid_assets": liquid, "months_covered": months},
    )


@_register(
    "DQ004",
    "Cash Flow Drivers non-empty",
    "rpt_mom_cash_flow_waterfall must have rows for recent months. "
    "Failure means the Cash Flow Drivers barchart renders blank.",
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
        f"rows={cnt} distinct_months={months}",
        query_result={"rows": cnt, "distinct_months": months},
    )


@_register(
    "DQ005",
    "Uncategorized Merchants are real",
    "viz_uncategorized_transactions_with_original_memo must have rows with "
    "merchant_display_name that is not 'None' or blank. "
    "Failure means Top Uncategorized Merchants shows a single 'None' row.",
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
        f"total_rows={total} valid_rows={valid}",
        query_result={"total_rows": total, "valid_rows": valid},
    )


@_register(
    "DQ006",
    "Liabilities > $0",
    "rpt_household_net_worth latest month must have total_liabilities > 0 "
    "(household has a mortgage). Failure means Asset & Liability panel shows "
    "Liabilities=$0 and D/A=0%.",
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
                           "No rows in rpt_household_net_worth")
    liab = float(row["total_liabilities"] or 0)
    passed = liab > 0
    return CheckResult(
        "DQ006", "Liabilities > $0", "", passed,
        f"month={row['budget_year_month']} total_liabilities={liab}",
        query_result={
            "month": row["budget_year_month"],
            "total_liabilities": liab,
            "total_assets": float(row["total_assets"] or 0),
            "net_worth": float(row["net_worth"] or 0),
        },
    )


@_register(
    "DQ007",
    "Savings/Expense ratios non-zero",
    "Latest month with income > 0 must have savings_rate_percent != 0 and "
    "expense_ratio_percent != 0. Failure means Savings & Expense panel shows "
    "all 0% values.",
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
                           "No months with total_income > 0")
    sr = float(row["savings_rate_percent"] or 0)
    er = float(row["expense_ratio_percent"] or 0)
    passed = sr != 0 and er != 0
    return CheckResult(
        "DQ007", "Savings/Expense ratios non-zero", "", passed,
        f"month={row['budget_year_month']} savings_rate={sr} expense_ratio={er}",
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
                           "No rows in rpt_executive_dashboard")
    forecast = float(row["forecasted_next_month_cash_flow"] or 0)
    passed = forecast != 0
    return CheckResult(
        "DQ008", "Forecast non-zero", "", passed,
        f"month={row['dashboard_month']} forecast={forecast}",
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
                           "No rows in rpt_executive_dashboard")
    income = float(row["monthly_income"] or 0)
    expenses = float(row["monthly_expenses"] or 0)
    passed = income > 0 and expenses > 0
    return CheckResult(
        "DQ009", "Executive dashboard row exists", "", passed,
        f"month={row['dashboard_month']} income={income} expenses={expenses}",
        query_result={
            "month": row["dashboard_month"],
            "monthly_income": income,
            "monthly_expenses": expenses,
            "health_score": float(row["overall_financial_health_score"] or 0),
        },
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
                    # Fill in description from registration
                    result.description = check["description"]
                    results.append(result)
                conn.commit()
            except Exception as exc:
                conn.rollback()  # Reset transaction after query errors (e.g. missing table)
                results.append(CheckResult(
                    check_id=check["id"],
                    name=check["name"],
                    description=check["description"],
                    passed=False,
                    detail=f"ERROR: {exc}",
                ))
    finally:
        conn.close()
    return results


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
                              "runtime_error": str(exc), "checks": []}))
        else:
            print(f"RUNTIME ERROR: {exc}", file=sys.stderr)
        sys.exit(2)

    if not results:
        # No checks ran at all — treat as runtime error
        if args.json:
            print(json.dumps({"total": 0, "passed": 0, "failed": 0,
                              "runtime_error": "no checks executed", "checks": []}))
        else:
            print("RUNTIME ERROR: no checks executed", file=sys.stderr)
        sys.exit(2)

    failures = [r for r in results if not r.passed]

    if args.json:
        payload = {
            "total": len(results),
            "passed": len(results) - len(failures),
            "failed": len(failures),
            "checks": [
                {
                    "check_id": r.check_id,
                    "name": r.name,
                    "description": r.description,
                    "passed": r.passed,
                    "detail": r.detail,
                }
                for r in results
            ],
        }
        print(json.dumps(payload, indent=2))
    else:
        for r in results:
            status = "PASS" if r.passed else "FAIL"
            print(f"[{status}] {r.check_id} {r.name}: {r.detail}")
        print(f"\n{len(results)} checks, {len(failures)} failed")

    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
