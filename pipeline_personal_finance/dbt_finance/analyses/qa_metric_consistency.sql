-- Quick metric consistency check between rpt and viz models
WITH rpt AS (
    SELECT 
        budget_year_month AS year_month,
        ROUND(total_income, 2)  AS rpt_income,
        ROUND(total_expenses, 2) AS rpt_expenses
    FROM {{ ref('rpt_monthly_budget_summary') }}
),
viz AS (
    SELECT 
        year_month,
        ROUND(income, 2)  AS viz_income,
        ROUND(expense, 2) AS viz_expenses
    FROM {{ ref('viz_income_vs_expense_by_month') }}
)
SELECT 
    COALESCE(r.year_month, v.year_month) AS year_month,
    r.rpt_income,
    v.viz_income,
    (v.viz_income - r.rpt_income) AS income_diff,
    r.rpt_expenses,
    v.viz_expenses,
    (v.viz_expenses - r.rpt_expenses) AS expense_diff
FROM rpt r
FULL OUTER JOIN viz v
  ON r.year_month = v.year_month
ORDER BY year_month;

