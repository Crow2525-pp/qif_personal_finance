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
        EXTRACT(YEAR FROM ft.transaction_date) AS year,
        dc.level_1_category AS category,
        {{ metric_expense(false, 'ft', 'dc') }} AS spending_amount
    FROM {{ ref('fct_transactions_enhanced') }} AS ft
    LEFT JOIN {{ ref('dim_categories_enhanced') }} AS dc
      ON ft.category_key = dc.category_key
    JOIN allowed a
      ON dc.level_1_category = a.category
    WHERE ft.transaction_date >= (DATE_TRUNC('year', CURRENT_DATE) - INTERVAL '1 year')::date
),
yearly_category AS (
    SELECT
        year,
        category,
        SUM(spending_amount) AS spending
    FROM base
    GROUP BY 1, 2
)
SELECT
    year
    {% if categories | length > 0 %}
      , {% for category in categories %}
          COALESCE(MAX(CASE WHEN category = '{{ category }}' THEN spending END), 0) AS "{{ category }}"{% if not loop.last %}, {% endif %}
        {% endfor %}
    {% else %}
      , SUM(spending) AS total_spending
    {% endif %}
FROM yearly_category
GROUP BY year
ORDER BY year
