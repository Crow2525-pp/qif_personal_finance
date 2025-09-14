{% set sql %}
  SELECT category FROM {{ ref('categories_allowed') }} ORDER BY display_order
{% endset %}

{% set results = run_query(sql) %}
{% if execute %}
  {% set categories = results.columns[0].values() %}
{% else %}
  {% set categories = [] %}
{% endif %}

WITH allowed AS (
    SELECT category FROM {{ ref('categories_allowed') }}
),
base AS (
    SELECT 
        ft.transaction_date,
        TO_CHAR(ft.transaction_date, 'YYYY-MM') AS year_month,
        dc.level_1_category AS category,
        {{ metric_expense(false, 'ft', 'dc') }} AS spending_amount
    FROM {{ ref('fct_transactions_enhanced') }} AS ft
    LEFT JOIN {{ ref('dim_categories_enhanced') }} AS dc
      ON ft.category_key = dc.category_key
    JOIN allowed a
      ON dc.level_1_category = a.category
    WHERE ft.transaction_date >= (DATE_TRUNC('month', CURRENT_DATE) - INTERVAL '23 months')::date
),
categories_as_columns AS (
    SELECT
        year_month,
        category,
        SUM(spending_amount) AS spending
    FROM base
    GROUP BY 1, 2
)
SELECT
    TO_DATE(year_month || '-01', 'YYYY-MM-DD') AS period_date,
    year_month
    {% if categories | length > 0 %}
      , {% for category in categories %}
          COALESCE(MAX(CASE WHEN category = '{{ category }}' THEN spending END), 0) AS "{{ category }}"{% if not loop.last %}, {% endif %}
        {% endfor %}
    {% else %}
      , SUM(spending) AS total_spending
    {% endif %}
FROM categories_as_columns
GROUP BY year_month, period_date
ORDER BY period_date
