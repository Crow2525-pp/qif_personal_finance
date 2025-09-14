-- Fails when monthly income/expense differs between rpt and viz outputs
WITH rpt AS (
  SELECT 
    budget_year_month AS year_month,
    ROUND(total_income::NUMERIC, 2)  AS rpt_income,
    ROUND(total_expenses::NUMERIC, 2) AS rpt_expenses
  FROM {{ ref('rpt_monthly_budget_summary') }}
),
viz AS (
  SELECT 
    year_month,
    ROUND(income::NUMERIC, 2)  AS viz_income,
    ROUND(expense::NUMERIC, 2) AS viz_expenses
  FROM {{ ref('viz_income_vs_expense_by_month') }}
),
cmp AS (
  SELECT 
    COALESCE(r.year_month, v.year_month) AS year_month,
    COALESCE(r.rpt_income, 0)   AS rpt_income,
    COALESCE(v.viz_income, 0)   AS viz_income,
    COALESCE(r.rpt_expenses, 0) AS rpt_expenses,
    COALESCE(v.viz_expenses, 0) AS viz_expenses
  FROM rpt r
  FULL OUTER JOIN viz v
    ON r.year_month = v.year_month
)
SELECT *
FROM cmp
WHERE ABS(viz_income - rpt_income) > 0.01
   OR ABS(viz_expenses - rpt_expenses) > 0.01
