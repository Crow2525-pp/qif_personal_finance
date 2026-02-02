{% set sql %}
  SELECT 'income' as type
  UNION ALL
  SELECT 'expense' as type
{% endset %}

{% set results = run_query(sql) %}
{% if execute %}
  {% set types = results.columns[0].values() %}
{% endif %}

WITH base AS (
    SELECT 
        TO_CHAR(ft.transaction_date, 'YYYY-MM') AS year_month,
        CASE 
          WHEN COALESCE(ft.is_income_transaction, FALSE) OR (ft.transaction_amount > 0 AND NOT COALESCE(ft.is_internal_transfer, FALSE))
            THEN ft.transaction_amount
          ELSE 0
        END AS income_amount,
        CASE 
          WHEN ft.transaction_amount < 0 AND NOT COALESCE(ft.is_internal_transfer, FALSE)
            THEN ABS(ft.transaction_amount)
          ELSE 0
        END AS expense_amount
    FROM {{ ref('fct_transactions') }} ft
    LEFT JOIN {{ ref('dim_categories') }} dc
      ON ft.category_key = dc.category_key
),
income_expense AS (
    SELECT
        year_month,
        SUM(income_amount)  AS income,
        SUM(expense_amount) AS expense
    FROM base 
    GROUP BY 1
)
SELECT
    TO_DATE(year_month || '-01', 'YYYY-MM-DD') AS period_date,
    year_month,
    income,
    expense
FROM income_expense
WHERE TO_DATE(year_month || '-01', 'YYYY-MM-DD') < DATE_TRUNC('month', CURRENT_DATE)
ORDER BY period_date
