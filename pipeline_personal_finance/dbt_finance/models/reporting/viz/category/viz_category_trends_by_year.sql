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
           extract(year from date) as year
    FROM {{ ref('reporting__fact_transactions') }} as trans
    left join {{ref('dim_category')}} as cat
        ON trans.category_foreign_key = cat.origin_key
),
yearly_category AS (
    SELECT
        year,
        category,
        SUM(CASE WHEN amount < 0 THEN -amount ELSE 0 END) AS spending
    FROM base
    GROUP BY 1, 2
)
SELECT
    year,
    {% for category in categories %}
      MAX(CASE WHEN lower(category) = lower('{{ category }}') THEN spending ELSE NULL END) AS "{{ category }}"
      {% if not loop.last %}, {% endif %}
    {% endfor %}
FROM yearly_category
GROUP BY year
ORDER BY year
