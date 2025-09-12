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
        to_char(transaction_date, 'YYYY-MM') AS year_month,
        transaction_amount,
        is_internal_transfer
    FROM {{ ref('fct_transactions_enhanced') }}
),
income_expense AS (
    SELECT
        year_month,
        SUM(CASE WHEN transaction_amount > 0 AND NOT COALESCE(is_internal_transfer, FALSE) THEN transaction_amount ELSE 0 END) AS income,
        SUM(CASE WHEN transaction_amount < 0 AND NOT COALESCE(is_internal_transfer, FALSE) THEN -transaction_amount ELSE 0 END) AS expense
    FROM base 
    GROUP BY 1
)
SELECT
    year_month,
    income,
    expense
FROM income_expense
ORDER BY year_month
