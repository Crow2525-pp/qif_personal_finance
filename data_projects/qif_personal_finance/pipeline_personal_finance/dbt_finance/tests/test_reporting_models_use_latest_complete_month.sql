WITH expected AS (
  SELECT {{ latest_complete_reporting_month() }} AS expected_month
),
budget_summary AS (
  SELECT
    'rpt_monthly_budget_summary' AS model_name,
    MAX(budget_year_month) AS actual_month
  FROM {{ ref('rpt_monthly_budget_summary') }}
),
household_net_worth AS (
  SELECT
    'rpt_household_net_worth' AS model_name,
    MAX(budget_year_month) AS actual_month
  FROM {{ ref('rpt_household_net_worth') }}
)
SELECT
  model_name,
  actual_month,
  expected_month
FROM budget_summary
CROSS JOIN expected
WHERE actual_month IS DISTINCT FROM expected_month

UNION ALL

SELECT
  model_name,
  actual_month,
  expected_month
FROM household_net_worth
CROSS JOIN expected
WHERE actual_month IS DISTINCT FROM expected_month
