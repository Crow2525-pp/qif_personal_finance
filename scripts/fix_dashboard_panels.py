"""
One-shot script to fix all 18 failing Grafana dashboard panels.
Run from the repo root.  Edits dashboard JSON files in-place, then
optionally pushes each updated dashboard to Grafana via the HTTP API.

Usage:
    python scripts/fix_dashboard_panels.py            # edit files only
    python scripts/fix_dashboard_panels.py --push     # edit + push to Grafana
"""

import argparse
import json
import os
from pathlib import Path

import requests

DASHBOARD_DIR = Path(__file__).resolve().parents[1] / "grafana" / "provisioning" / "dashboards"
GRAFANA_URL   = os.environ.get("GRAFANA_URL", "http://192.168.1.103:3001")
GRAFANA_TOKEN = os.environ.get("GRAFANA_TOKEN", "")

# ---------------------------------------------------------------------------
# Inline SQL for panels that previously used the missing
# reporting.viz_uncategorized_transactions_with_original_memo view.
# ---------------------------------------------------------------------------

_UNCATEGORIZED_SQL_WITH_PRIORITY = """WITH uncategorized AS (
  SELECT
    COALESCE(NULLIF(TRIM(ft.transaction_memo), ''), NULLIF(TRIM(ft.transaction_description), '')) AS original_memo,
    COUNT(*) AS transaction_count,
    SUM(ABS(ft.transaction_amount)) AS total_amount,
    MAX(ft.transaction_date) AS last_transaction_date
  FROM reporting.fct_transactions ft
  LEFT JOIN reporting.dim_categories dc ON ft.category_key = dc.category_key
  WHERE dc.level_1_category = 'Uncategorized'
    AND ft.transaction_amount < 0
    AND NOT COALESCE(ft.is_internal_transfer, FALSE)
    AND COALESCE(NULLIF(TRIM(ft.transaction_memo), ''), NULLIF(TRIM(ft.transaction_description), '')) IS NOT NULL
  GROUP BY COALESCE(NULLIF(TRIM(ft.transaction_memo), ''), NULLIF(TRIM(ft.transaction_description), ''))
  HAVING COUNT(*) >= 2 OR SUM(ABS(ft.transaction_amount)) >= 100
),
data AS (
  SELECT
    original_memo,
    transaction_count,
    ROUND(total_amount, 2) AS total_spend,
    last_transaction_date,
    CASE
      WHEN total_amount >= 1000 THEN 'HIGH'
      WHEN total_amount >= 500 THEN 'MEDIUM'
      WHEN total_amount >= 100 THEN 'LOW'
      ELSE 'MINOR'
    END AS priority_level
  FROM uncategorized
  ORDER BY total_amount DESC
  LIMIT 10
)
SELECT
  original_memo AS "Merchant",
  transaction_count AS "Txn Count",
  total_spend AS "Total Spend",
  last_transaction_date AS "Last Seen",
  priority_level AS "Priority"
FROM data
UNION ALL
SELECT 'None', 0, 0, NULL::date, 'N/A'
WHERE NOT EXISTS (SELECT 1 FROM data)"""

_UNCATEGORIZED_SQL_SPLIT_PART = """WITH uncategorized AS (
  SELECT
    SPLIT_PART(
      COALESCE(NULLIF(TRIM(ft.transaction_memo), ''), NULLIF(TRIM(ft.transaction_description), ''), 'Unknown'),
      ' - ', 1
    ) AS merchant,
    COUNT(*) AS txn_count,
    SUM(ABS(ft.transaction_amount)) AS total_spend,
    MAX(ft.transaction_date) AS last_seen
  FROM reporting.fct_transactions ft
  LEFT JOIN reporting.dim_categories dc ON ft.category_key = dc.category_key
  WHERE dc.level_1_category = 'Uncategorized'
    AND ft.transaction_amount < 0
    AND NOT COALESCE(ft.is_internal_transfer, FALSE)
    AND COALESCE(NULLIF(TRIM(ft.transaction_memo), ''), NULLIF(TRIM(ft.transaction_description), '')) IS NOT NULL
  GROUP BY SPLIT_PART(
    COALESCE(NULLIF(TRIM(ft.transaction_memo), ''), NULLIF(TRIM(ft.transaction_description), ''), 'Unknown'),
    ' - ', 1
  )
  HAVING COUNT(*) >= 2 OR SUM(ABS(ft.transaction_amount)) >= 100
),
data AS (
  SELECT merchant, txn_count, ROUND(total_spend, 2) AS total_spend, last_seen
  FROM uncategorized
  ORDER BY total_spend DESC
  LIMIT 10
)
SELECT
  merchant AS "Merchant",
  txn_count AS "Txn Count",
  total_spend AS "Total Spend",
  last_seen AS "Last Seen"
FROM data
UNION ALL
SELECT 'None', 0, 0, NULL::date
WHERE NOT EXISTS (SELECT 1 FROM data)"""

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def load(fname):
    path = DASHBOARD_DIR / fname
    with open(path, encoding="utf-8") as f:
        return json.load(f)

def save(fname, data):
    path = DASHBOARD_DIR / fname
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"  saved {fname}")

def iter_panels(dashboard):
    for p in dashboard.get("panels", []):
        subs = p.get("panels", [])
        if subs:
            yield from subs
        else:
            yield p

def panel_by_id(dashboard, pid):
    for p in iter_panels(dashboard):
        if p.get("id") == pid:
            return p
    return None

def set_sql(panel, new_sql, ref_id="A"):
    for t in panel.get("targets", []):
        if t.get("refId", "A") == ref_id:
            t["rawSql"] = new_sql
            return
    if panel.get("targets"):
        panel["targets"][0]["rawSql"] = new_sql

def replace_all_sql(panel, old, new):
    for t in panel.get("targets", []):
        if "rawSql" in t:
            t["rawSql"] = t["rawSql"].replace(old, new)

# ---------------------------------------------------------------------------
# Fix functions per dashboard
# ---------------------------------------------------------------------------

def fix_cash_flow_analysis(fname="cash-flow-analysis-dashboard.json"):
    d = load(fname)
    p = panel_by_id(d, 904)
    if p:
        set_sql(p, _UNCATEGORIZED_SQL_WITH_PRIORITY)
        print("  [cash-flow] panel 904: uncategorized -> inline SQL")
    save(fname, d)


def fix_outflows_insights(fname="outflows-insights-dashboard.json"):
    d = load(fname)
    for pid in (5, 7, 10):
        p = panel_by_id(d, pid)
        if p:
            replace_all_sql(p, "uncategorized as amount", "uncategorized_amount as amount")
            replace_all_sql(p, 'uncategorized as "Uncategorized"', 'uncategorized_amount as "Uncategorized"')
            replace_all_sql(p, 'uncategorized as "Uncategorized Amount"', 'uncategorized_amount as "Uncategorized Amount"')
            print(f"  [outflows] panel {pid}: uncategorized -> uncategorized_amount")
    p906 = panel_by_id(d, 906)
    if p906:
        set_sql(p906, _UNCATEGORIZED_SQL_SPLIT_PART)
        print("  [outflows] panel 906: uncategorized -> inline SQL")
    save(fname, d)


def fix_transaction_analysis(fname="transaction-analysis-dashboard.json"):
    d = load(fname)
    p = panel_by_id(d, 908)
    if p:
        set_sql(p, _UNCATEGORIZED_SQL_WITH_PRIORITY)
        print("  [transaction] panel 908: uncategorized -> inline SQL")
    save(fname, d)


def fix_grocery(fname="grocery-spending-dashboard.json"):
    d = load(fname)
    p9 = panel_by_id(d, 9)
    if p9:
        old_cte = (
            "min_store AS (\n"
            "  SELECT \n"
            "    grocery_store,\n"
            "    avg_monthly_spend,\n"
            "    FIRST_VALUE(grocery_store) OVER (ORDER BY avg_monthly_spend) AS cheapest_store,\n"
            "    FIRST_VALUE(avg_monthly_spend) OVER (ORDER BY avg_monthly_spend) AS cheapest_price\n"
            "  FROM store_averages\n"
            ")"
        )
        new_cte = (
            "min_store AS (\n"
            "  SELECT \n"
            "    grocery_store,\n"
            "    avg_monthly_spend,\n"
            "    months_tracked,\n"
            "    FIRST_VALUE(grocery_store) OVER (ORDER BY avg_monthly_spend) AS cheapest_store,\n"
            "    FIRST_VALUE(avg_monthly_spend) OVER (ORDER BY avg_monthly_spend) AS cheapest_price\n"
            "  FROM store_averages\n"
            ")"
        )
        replace_all_sql(p9, old_cte, new_cte)
        print("  [grocery] panel 9: months_tracked added to min_store CTE")
    p13 = panel_by_id(d, 13)
    if p13:
        replace_all_sql(p13, "ORDER BY grocery_store, year_month", "ORDER BY year_month, grocery_store")
        print("  [grocery] panel 13: ORDER BY fixed (year_month first)")
    save(fname, d)


def fix_household_net_worth(fname="household-net-worth-dashboard.json"):
    d = load(fname)
    p = panel_by_id(d, 10)
    if p:
        replace_all_sql(p,
            "make_date(ft.transaction_year, ft.transaction_month, 1)",
            "make_date(ft.transaction_year::int, ft.transaction_month::int, 1)")
        print("  [net-worth] panel 10: make_date cast to int")
    save(fname, d)


_BUDGET_PANEL103_SQL = """WITH latest_two_months AS (
  SELECT budget_year_month, ROW_NUMBER() OVER (ORDER BY budget_year_month DESC) as rn
  FROM reporting.rpt_category_spending_trends
  WHERE budget_year_month < TO_CHAR(DATE_TRUNC('month', CURRENT_DATE), 'YYYY-MM')
  GROUP BY budget_year_month
  ORDER BY budget_year_month DESC
  LIMIT 2
),
variance_categories AS (
  SELECT level_1_category,
    ABS(SUM(CASE WHEN budget_year_month = (SELECT budget_year_month FROM latest_two_months WHERE rn = 1)
      THEN monthly_spending ELSE -COALESCE(monthly_spending, 0) END)) as variance
  FROM reporting.rpt_category_spending_trends
  WHERE budget_year_month IN (SELECT budget_year_month FROM latest_two_months)
    AND level_1_category NOT IN ('Uncategorized', 'Bank Transaction', 'Salary')
  GROUP BY level_1_category
  ORDER BY variance DESC
  LIMIT 1
)
SELECT
  ft.transaction_date::date AS transaction_date,
  COALESCE(NULLIF(TRIM(ft.transaction_memo), ''), NULLIF(TRIM(ft.transaction_description), ''), 'Unknown') AS merchant,
  ft.transaction_amount_abs AS amount,
  dc.level_1_category AS category
FROM reporting.fct_transactions ft
LEFT JOIN reporting.dim_categories dc ON ft.category_key = dc.category_key
WHERE dc.level_1_category = (SELECT level_1_category FROM variance_categories)
  AND DATE_TRUNC('month', ft.transaction_date) = (
    SELECT TO_DATE(budget_year_month || '-01', 'YYYY-MM-DD') FROM latest_two_months WHERE rn = 1
  )
  AND ft.transaction_amount < 0
  AND NOT COALESCE(ft.is_internal_transfer, FALSE)
ORDER BY ft.transaction_amount_abs DESC
LIMIT 5"""

_BUDGET_PANEL105_SQL = """WITH latest_month AS (
  SELECT MAX(budget_year_month) AS budget_year_month
  FROM reporting.rpt_category_spending_trends
  WHERE budget_year_month < TO_CHAR(DATE_TRUNC('month', CURRENT_DATE), 'YYYY-MM')
),
prior_year_month AS (
  SELECT TO_CHAR(TO_DATE(budget_year_month || '-01', 'YYYY-MM-DD') - INTERVAL '1 year', 'YYYY-MM') AS budget_year_month
  FROM latest_month
),
comparison_months AS (
  SELECT budget_year_month FROM latest_month
  UNION ALL
  SELECT budget_year_month FROM prior_year_month
),
variance_categories AS (
  SELECT level_1_category,
    ABS(SUM(CASE WHEN budget_year_month = (SELECT budget_year_month FROM latest_month)
      THEN monthly_spending ELSE -COALESCE(monthly_spending, 0) END)) as variance
  FROM reporting.rpt_category_spending_trends
  WHERE budget_year_month IN (SELECT budget_year_month FROM comparison_months)
    AND level_1_category NOT IN ('Uncategorized', 'Bank Transaction', 'Salary')
  GROUP BY level_1_category
  ORDER BY variance DESC
  LIMIT 1
)
SELECT
  ft.transaction_date::date AS transaction_date,
  COALESCE(NULLIF(TRIM(ft.transaction_memo), ''), NULLIF(TRIM(ft.transaction_description), ''), 'Unknown') AS merchant,
  ft.transaction_amount_abs AS amount,
  dc.level_1_category AS category
FROM reporting.fct_transactions ft
LEFT JOIN reporting.dim_categories dc ON ft.category_key = dc.category_key
WHERE dc.level_1_category = (SELECT level_1_category FROM variance_categories)
  AND DATE_TRUNC('month', ft.transaction_date) = (
    SELECT TO_DATE(budget_year_month || '-01', 'YYYY-MM-DD') FROM latest_month
  )
  AND ft.transaction_amount < 0
  AND NOT COALESCE(ft.is_internal_transfer, FALSE)
ORDER BY ft.transaction_amount_abs DESC
LIMIT 5"""


def fix_monthly_budget(fname="monthly-budget-summary-dashboard.json"):
    d = load(fname)
    # Panel 11 with budget_cockpit — add fallback row
    p11 = None
    for p in iter_panels(d):
        if p.get("id") == 11:
            for t in p.get("targets", []):
                if "budget_cockpit" in t.get("rawSql", ""):
                    p11 = p
                    break
        if p11:
            break
    if p11:
        new_sql = (
            "WITH data AS (\n"
            "  SELECT\n"
            "    level_1_category AS \"Category\",\n"
            "    months_of_consecutive_overspend AS \"Consecutive Months\",\n"
            "    ROUND(suggested_budget_amount, 0) AS \"Suggested Budget\",\n"
            "    ROUND(total_overspend, 0) AS \"Total Overspend\",\n"
            "    ROUND(reduction_pct, 1) AS \"Reduction %\",\n"
            "    adjustment_rationale AS \"Rationale\",\n"
            "    priority\n"
            "  FROM reporting.rpt_budget_cockpit_adjustment_suggestions\n"
            "  ORDER BY priority ASC, total_overspend DESC\n"
            "  LIMIT 10\n"
            ")\n"
            "SELECT * FROM data\n"
            "UNION ALL\n"
            "SELECT 'No adjustments needed', NULL, NULL, NULL, NULL, 'All categories within budget', NULL\n"
            "WHERE NOT EXISTS (SELECT 1 FROM data)"
        )
        set_sql(p11, new_sql)
        print("  [budget] panel 11: fallback row added for empty table")

    p103 = panel_by_id(d, 103)
    if p103:
        set_sql(p103, _BUDGET_PANEL103_SQL)
        print("  [budget] panel 103: transformation.fct_transactions -> reporting (inline SQL)")
    p105 = panel_by_id(d, 105)
    if p105:
        set_sql(p105, _BUDGET_PANEL105_SQL)
        print("  [budget] panel 105: transformation.fct_transactions -> reporting (inline SQL)")
    save(fname, d)


def fix_mortgage(fname="mortgage-payoff-dashboard.json"):
    d = load(fname)
    for pid in (2, 3, 4, 5):
        p = panel_by_id(d, pid)
        if not p:
            continue
        replace_all_sql(p,
            "ABS(COALESCE(adelaide_homeloan, 0) + COALESCE(bendigo_homeloan, 0)) AS balance",
            "ABS(COALESCE(homeloan, 0)) AS balance")
        replace_all_sql(p,
            "WHERE adelaide_homeloan IS NOT NULL OR bendigo_homeloan IS NOT NULL",
            "WHERE homeloan IS NOT NULL")
        replace_all_sql(p,
            'COALESCE("adelaide_homeloan_MoM", 0) + COALESCE("bendigo_homeloan_MoM", 0) AS reduction',
            'COALESCE("homeloan_MoM", 0) AS reduction')
        replace_all_sql(p,
            'WHERE COALESCE("adelaide_homeloan_MoM", 0) + COALESCE("bendigo_homeloan_MoM", 0) IS NOT NULL',
            'WHERE "homeloan_MoM" IS NOT NULL')
        print(f"  [mortgage] panel {pid}: column names fixed")
    p6 = panel_by_id(d, 6)
    if p6:
        replace_all_sql(p6, "estimated_annual_interest_rate_pct", "estimated_interest_rate_pct")
        print("  [mortgage] panel 6: estimated_annual_interest_rate_pct -> estimated_interest_rate_pct")
    save(fname, d)


def fix_year_over_year(fname="year-over-year-comparison-dashboard.json"):
    d = load(fname)
    p = panel_by_id(d, 13)
    if p:
        new_sql = (
            "(SELECT\n"
            "  'Top Expense Driver 1' as \"Category\",\n"
            "  top_expense_driver_1 as \"Driver\"\n"
            "FROM reporting.rpt_year_over_year_comparison\n"
            "WHERE comparison_year < EXTRACT(YEAR FROM CURRENT_DATE)\n"
            "ORDER BY comparison_year DESC\n"
            "LIMIT 1)\n"
            "UNION ALL\n"
            "(SELECT\n"
            "  'Top Expense Driver 2' as \"Category\",\n"
            "  top_expense_driver_2 as \"Driver\"\n"
            "FROM reporting.rpt_year_over_year_comparison\n"
            "WHERE comparison_year < EXTRACT(YEAR FROM CURRENT_DATE)\n"
            "ORDER BY comparison_year DESC\n"
            "LIMIT 1)\n"
            "UNION ALL\n"
            "(SELECT\n"
            "  'Top Net Worth Driver' as \"Category\",\n"
            "  top_net_worth_driver_1 as \"Driver\"\n"
            "FROM reporting.rpt_year_over_year_comparison\n"
            "WHERE comparison_year < EXTRACT(YEAR FROM CURRENT_DATE)\n"
            "ORDER BY comparison_year DESC\n"
            "LIMIT 1)"
        )
        set_sql(p, new_sql)
        print("  [yoy] panel 13: UNION ALL members wrapped in parens")
    save(fname, d)


# ---------------------------------------------------------------------------
# Grafana API push
# ---------------------------------------------------------------------------

def push_dashboard(fname):
    path = DASHBOARD_DIR / fname
    with open(path, encoding="utf-8") as f:
        dashboard_json = json.load(f)
    payload = {"dashboard": dashboard_json, "overwrite": True, "folderId": 0}
    headers = {"Authorization": f"Bearer {GRAFANA_TOKEN}", "Content-Type": "application/json"}
    resp = requests.post(f"{GRAFANA_URL}/api/dashboards/db", json=payload, headers=headers, timeout=30)
    if resp.status_code == 200:
        print(f"  pushed {fname}")
    else:
        print(f"  WARN push {fname}: {resp.status_code} {resp.text[:200]}")


_OUTFLOWS_PANEL14_SQL = """WITH latest_two_months AS (
  SELECT budget_year_month, ROW_NUMBER() OVER (ORDER BY budget_year_month DESC) as rn
  FROM reporting.rpt_category_spending_trends
  WHERE budget_year_month < TO_CHAR(DATE_TRUNC('month', CURRENT_DATE), 'YYYY-MM')
  GROUP BY budget_year_month
  ORDER BY budget_year_month DESC
  LIMIT 2
),
variance_categories AS (
  SELECT level_1_category,
    ABS(SUM(CASE WHEN budget_year_month = (SELECT budget_year_month FROM latest_two_months WHERE rn = 1)
      THEN monthly_spending ELSE -COALESCE(monthly_spending, 0) END)) as variance
  FROM reporting.rpt_category_spending_trends
  WHERE budget_year_month IN (SELECT budget_year_month FROM latest_two_months)
    AND level_1_category NOT IN ('Uncategorized', 'Bank Transaction', 'Salary')
  GROUP BY level_1_category
  ORDER BY variance DESC
  LIMIT 1
)
SELECT
  ft.transaction_date::date AS transaction_date,
  COALESCE(NULLIF(TRIM(ft.transaction_memo), ''), NULLIF(TRIM(ft.transaction_description), ''), 'Unknown') AS merchant,
  ft.transaction_amount_abs AS amount,
  dc.level_1_category AS category
FROM reporting.fct_transactions ft
LEFT JOIN reporting.dim_categories dc ON ft.category_key = dc.category_key
WHERE dc.level_1_category = (SELECT level_1_category FROM variance_categories)
  AND DATE_TRUNC('month', ft.transaction_date) = (
    SELECT TO_DATE(budget_year_month || '-01', 'YYYY-MM-DD') FROM latest_two_months WHERE rn = 1
  )
  AND ft.transaction_amount < 0
  AND NOT COALESCE(ft.is_internal_transfer, FALSE)
ORDER BY ft.transaction_amount_abs DESC
LIMIT 5"""

_OUTFLOWS_PANEL16_SQL = """WITH latest_month AS (
  SELECT MAX(budget_year_month) AS budget_year_month
  FROM reporting.rpt_category_spending_trends
  WHERE budget_year_month < TO_CHAR(DATE_TRUNC('month', CURRENT_DATE), 'YYYY-MM')
),
prior_year_month AS (
  SELECT TO_CHAR(TO_DATE(budget_year_month || '-01', 'YYYY-MM-DD') - INTERVAL '1 year', 'YYYY-MM') AS budget_year_month
  FROM latest_month
),
comparison_months AS (
  SELECT budget_year_month FROM latest_month
  UNION ALL
  SELECT budget_year_month FROM prior_year_month
),
variance_categories AS (
  SELECT level_1_category,
    ABS(SUM(CASE WHEN budget_year_month = (SELECT budget_year_month FROM latest_month)
      THEN monthly_spending ELSE -COALESCE(monthly_spending, 0) END)) as variance
  FROM reporting.rpt_category_spending_trends
  WHERE budget_year_month IN (SELECT budget_year_month FROM comparison_months)
    AND level_1_category NOT IN ('Uncategorized', 'Bank Transaction', 'Salary')
  GROUP BY level_1_category
  ORDER BY variance DESC
  LIMIT 1
)
SELECT
  ft.transaction_date::date AS transaction_date,
  COALESCE(NULLIF(TRIM(ft.transaction_memo), ''), NULLIF(TRIM(ft.transaction_description), ''), 'Unknown') AS merchant,
  ft.transaction_amount_abs AS amount,
  dc.level_1_category AS category
FROM reporting.fct_transactions ft
LEFT JOIN reporting.dim_categories dc ON ft.category_key = dc.category_key
WHERE dc.level_1_category = (SELECT level_1_category FROM variance_categories)
  AND DATE_TRUNC('month', ft.transaction_date) = (
    SELECT TO_DATE(budget_year_month || '-01', 'YYYY-MM-DD') FROM latest_month
  )
  AND ft.transaction_amount < 0
  AND NOT COALESCE(ft.is_internal_transfer, FALSE)
ORDER BY ft.transaction_amount_abs DESC
LIMIT 5"""

_TXN_ANOMALIES_SQL = """WITH merchant_baseline AS (
  SELECT
    COALESCE(NULLIF(TRIM(ft.transaction_memo), ''), NULLIF(TRIM(ft.transaction_description), ''), 'Unknown') AS merchant_name,
    COUNT(*) AS merchant_12m_count,
    AVG(ft.transaction_amount_abs) AS merchant_12m_avg
  FROM reporting.fct_transactions ft
  WHERE ft.transaction_date >= CURRENT_DATE - INTERVAL '12 months'
    AND ft.transaction_amount < 0
    AND NOT COALESCE(ft.is_internal_transfer, FALSE)
  GROUP BY COALESCE(NULLIF(TRIM(ft.transaction_memo), ''), NULLIF(TRIM(ft.transaction_description), ''), 'Unknown')
  HAVING COUNT(*) >= 2
),
recent_txns AS (
  SELECT
    ft.transaction_date,
    da.account_name,
    COALESCE(NULLIF(TRIM(ft.transaction_memo), ''), NULLIF(TRIM(ft.transaction_description), ''), 'Unknown') AS merchant_name,
    dc.level_1_category AS category_name,
    ft.transaction_amount_abs AS amount_abs
  FROM reporting.fct_transactions ft
  LEFT JOIN reporting.dim_accounts da ON ft.account_key = da.account_key
  LEFT JOIN reporting.dim_categories dc ON ft.category_key = dc.category_key
  WHERE ft.transaction_date >= CURRENT_DATE - INTERVAL '3 months'
    AND ft.transaction_amount < 0
    AND NOT COALESCE(ft.is_internal_transfer, FALSE)
)
SELECT
  rt.transaction_date::date,
  rt.account_name,
  rt.merchant_name,
  rt.category_name,
  rt.amount_abs,
  ROUND(mb.merchant_12m_avg::numeric, 2) AS merchant_12m_avg,
  ROUND(((rt.amount_abs - mb.merchant_12m_avg) / NULLIF(mb.merchant_12m_avg, 0) * 100)::numeric, 1) AS variance_from_avg_pct,
  mb.merchant_12m_count,
  CASE
    WHEN rt.amount_abs > mb.merchant_12m_avg * 2 THEN 'HIGH'
    WHEN rt.amount_abs > mb.merchant_12m_avg * 1.5 THEN 'MEDIUM'
    ELSE 'LOW'
  END AS anomaly_severity_label
FROM recent_txns rt
JOIN merchant_baseline mb ON rt.merchant_name = mb.merchant_name
WHERE rt.amount_abs > mb.merchant_12m_avg * 1.3
ORDER BY variance_from_avg_pct DESC
LIMIT 30"""

_TXN_NEEDS_REVIEW_SQL = """WITH merchant_counts AS (
  SELECT
    COALESCE(NULLIF(TRIM(ft.transaction_memo), ''), NULLIF(TRIM(ft.transaction_description), ''), 'Unknown') AS merchant_name,
    COUNT(*) AS merchant_12m_transaction_count
  FROM reporting.fct_transactions ft
  WHERE ft.transaction_date >= CURRENT_DATE - INTERVAL '12 months'
    AND ft.transaction_amount < 0
    AND NOT COALESCE(ft.is_internal_transfer, FALSE)
  GROUP BY COALESCE(NULLIF(TRIM(ft.transaction_memo), ''), NULLIF(TRIM(ft.transaction_description), ''), 'Unknown')
)
SELECT
  ft.transaction_date::date,
  da.account_name,
  COALESCE(NULLIF(TRIM(ft.transaction_memo), ''), NULLIF(TRIM(ft.transaction_description), ''), 'Unknown') AS merchant_name,
  ft.transaction_amount_abs AS amount_abs,
  dc.level_1_category,
  CASE
    WHEN dc.level_1_category = 'Uncategorized' THEN 'Uncategorized transaction'
    WHEN COALESCE(mc.merchant_12m_transaction_count, 0) <= 1 THEN 'New merchant'
    WHEN ft.transaction_amount_abs >= 500 THEN 'High value transaction'
    ELSE 'Review recommended'
  END AS primary_review_reason,
  CASE WHEN COALESCE(mc.merchant_12m_transaction_count, 0) <= 1 THEN TRUE ELSE FALSE END AS is_new_merchant,
  COALESCE(mc.merchant_12m_transaction_count, 0) AS merchant_12m_transaction_count,
  CASE
    WHEN ft.transaction_amount_abs >= 1000 THEN 'HIGH'
    WHEN ft.transaction_amount_abs >= 200 THEN 'MEDIUM'
    ELSE 'LOW'
  END AS priority_label,
  CASE
    WHEN ft.transaction_date >= DATE_TRUNC('month', CURRENT_DATE) THEN 'CURRENT_MONTH'
    ELSE 'RECENT'
  END AS queue_status
FROM reporting.fct_transactions ft
LEFT JOIN reporting.dim_accounts da ON ft.account_key = da.account_key
LEFT JOIN reporting.dim_categories dc ON ft.category_key = dc.category_key
LEFT JOIN merchant_counts mc
  ON COALESCE(NULLIF(TRIM(ft.transaction_memo), ''), NULLIF(TRIM(ft.transaction_description), ''), 'Unknown') = mc.merchant_name
WHERE ft.transaction_date >= CURRENT_DATE - INTERVAL '3 months'
  AND ft.transaction_amount < 0
  AND NOT COALESCE(ft.is_internal_transfer, FALSE)
  AND (
    dc.level_1_category = 'Uncategorized'
    OR COALESCE(mc.merchant_12m_transaction_count, 0) <= 1
    OR ft.transaction_amount_abs >= 500
  )
ORDER BY
  CASE WHEN ft.transaction_amount_abs >= 1000 THEN 1 WHEN ft.transaction_amount_abs >= 200 THEN 2 ELSE 3 END ASC,
  ft.transaction_amount_abs DESC
LIMIT 40"""


def fix_outflows_remaining(fname="outflows-insights-dashboard.json"):
    d = load(fname)
    p14 = panel_by_id(d, 14)
    if p14:
        set_sql(p14, _OUTFLOWS_PANEL14_SQL)
        print("  [outflows] panel 14: transformation.fct_transactions -> reporting (inline SQL)")
    p16 = panel_by_id(d, 16)
    if p16:
        set_sql(p16, _OUTFLOWS_PANEL16_SQL)
        print("  [outflows] panel 16: transformation.fct_transactions -> reporting (inline SQL)")
    save(fname, d)


def fix_transaction_analysis_remaining(fname="transaction-analysis-dashboard.json"):
    d = load(fname)
    p7 = panel_by_id(d, 7)
    if p7:
        set_sql(p7, _TXN_ANOMALIES_SQL)
        print("  [transaction] panel 7: viz.viz_transaction_anomalies -> inline SQL")
    p8 = panel_by_id(d, 8)
    if p8:
        set_sql(p8, _TXN_NEEDS_REVIEW_SQL)
        print("  [transaction] panel 8: viz.viz_transactions_needs_review_queue -> inline SQL")
    save(fname, d)


FIXES = [
    ("cash-flow-analysis-dashboard.json",       fix_cash_flow_analysis),
    ("outflows-insights-dashboard.json",         fix_outflows_insights),
    ("outflows-insights-dashboard.json",         fix_outflows_remaining),
    ("transaction-analysis-dashboard.json",      fix_transaction_analysis),
    ("transaction-analysis-dashboard.json",      fix_transaction_analysis_remaining),
    ("grocery-spending-dashboard.json",          fix_grocery),
    ("household-net-worth-dashboard.json",       fix_household_net_worth),
    ("monthly-budget-summary-dashboard.json",    fix_monthly_budget),
    ("mortgage-payoff-dashboard.json",           fix_mortgage),
    ("year-over-year-comparison-dashboard.json", fix_year_over_year),
]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--push", action="store_true")
    args = parser.parse_args()

    for fname, fix_fn in FIXES:
        print(f"\n{fname}")
        fix_fn()
        if args.push:
            push_dashboard(fname)

    print("\nDone.")


if __name__ == "__main__":
    main()
