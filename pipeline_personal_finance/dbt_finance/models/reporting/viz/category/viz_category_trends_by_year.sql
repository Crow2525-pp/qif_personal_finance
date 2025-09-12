{% set sql %}
  SELECT DISTINCT lower(level_1_category) AS category
  FROM {{ ref('dim_categories_enhanced') }}
  WHERE level_1_category IS NOT NULL
{% endset %}

{% set results = run_query(sql) %}
{% if execute %}
  {% set categories = results.columns[0].values() %}
{% else %}
  {% set categories = [] %}
{% endif %}

WITH base AS (
    SELECT 
        extract(year FROM ft.transaction_date) AS year,
        dc.level_1_category AS category,
        ft.transaction_amount
    FROM {{ ref('fct_transactions_enhanced') }} AS ft
    LEFT JOIN {{ ref('dim_categories_enhanced') }} AS dc
      ON ft.category_key = dc.category_key
    WHERE NOT COALESCE(ft.is_internal_transfer, FALSE)
),
yearly_category AS (
    SELECT
        year,
        category,
        SUM(CASE WHEN transaction_amount < 0 THEN -transaction_amount ELSE 0 END) AS spending
    FROM base
    GROUP BY 1, 2
)
SELECT
    year
    {% if categories | length > 0 %}
      , {% for category in categories %}
          MAX(CASE WHEN lower(category) = lower('{{ category }}') THEN spending END) AS "{{ category }}"{% if not loop.last %}, {% endif %}
        {% endfor %}
    {% else %}
      , SUM(spending) AS total_spending
    {% endif %}
FROM yearly_category
GROUP BY year
ORDER BY year
