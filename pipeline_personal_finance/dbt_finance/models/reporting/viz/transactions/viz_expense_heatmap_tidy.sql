WITH base AS (
  SELECT 
    DATE_TRUNC('month', ft.transaction_date)::date AS period_date,
    EXTRACT(YEAR FROM ft.transaction_date) AS year,
    TO_CHAR(ft.transaction_date, 'Mon') AS month_label,
    {{ metric_expense(false, 'ft', 'dc') }} AS expense_amount
  FROM {{ ref('fct_transactions_enhanced') }} ft
  LEFT JOIN {{ ref('dim_categories_enhanced') }} dc
    ON ft.category_key = dc.category_key
)
SELECT 
  period_date,
  year,
  month_label,
  SUM(expense_amount) AS amount
FROM base
GROUP BY period_date, year, month_label
ORDER BY period_date

