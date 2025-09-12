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
    SELECT *,
           to_char(date, 'YYYY-MM') as year_month
    FROM {{ ref('reporting__fact_transactions') }}
),
income_expense AS (
    SELECT
        year_month,
        SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) AS income,
        SUM(CASE WHEN amount < 0 THEN -amount ELSE 0 END) AS expense
    FROM base
    GROUP BY 1
)
SELECT
    year_month,
    income,
    expense
FROM income_expense
ORDER BY year_month
