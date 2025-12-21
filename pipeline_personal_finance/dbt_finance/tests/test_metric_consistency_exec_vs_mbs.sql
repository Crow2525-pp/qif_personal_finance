-- Validate Executive Dashboard metrics match Monthly Budget Summary for the last complete month
WITH exec_latest AS (
  SELECT 
    dashboard_month,
    dashboard_year,
    dashboard_month_num,
    monthly_savings_rate_percent_pct AS exec_savings_pct,
    expense_to_income_ratio_pct     AS exec_expense_pct
  FROM {{ ref('rpt_executive_dashboard') }}
  ORDER BY dashboard_year DESC, dashboard_month_num DESC
  LIMIT 1
),
mbs AS (
  SELECT 
    budget_year_month,
    (savings_rate_percent * 100)::numeric    AS mbs_savings_pct,
    (expense_ratio_percent * 100)::numeric   AS mbs_expense_pct
  FROM {{ ref('rpt_monthly_budget_summary') }}
  WHERE budget_year_month = (SELECT dashboard_month FROM exec_latest)
)
SELECT *
FROM (
  SELECT 
    e.dashboard_month,
    e.exec_savings_pct,
    m.mbs_savings_pct,
    e.exec_expense_pct,
    m.mbs_expense_pct
  FROM exec_latest e
  JOIN mbs m ON m.budget_year_month = e.dashboard_month
) cmp
WHERE ABS(exec_savings_pct - mbs_savings_pct) > 0.1
   OR ABS(exec_expense_pct - mbs_expense_pct) > 0.1
