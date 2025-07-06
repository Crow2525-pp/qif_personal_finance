{% set sql %}
  SELECT DISTINCT lower(category) as category
  FROM {{ ref('dim_category') }}
  WHERE category IS NOT NULL
{% endset %}

{% set results = run_query(sql) %}
{% if execute %}
  {% set categories = results.columns[0].values() %}
{% endif %}

WITH base AS (
    SELECT *,
           to_char(date, 'YYYY-MM') as year_month
    FROM {{ ref('reporting__fact_transactions') }} as trans
    left join {{ref('dim_category')}} as cat
        ON trans.category_foreign_key = cat.origin_key
),
categories_as_columns AS (
    SELECT
        year_month,
        category,
        SUM(CASE WHEN amount < 0 THEN -amount ELSE 0 END) AS spending
    FROM base
    GROUP BY 1, 2
)
SELECT
    year_month,
    {% for category in categories %}
      MAX(CASE WHEN lower(category) = lower('{{ category }}') THEN spending ELSE NULL END) AS "{{ category }}"
      {% if not loop.last %}, {% endif %}
    {% endfor %}
FROM categories_as_columns
GROUP BY year_month
ORDER BY year_month
