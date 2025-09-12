{% set sql %}
  SELECT DISTINCT lower(origin_key) as account_foreign_key
  FROM {{ ref('dim_account') }}
  WHERE origin_key IS NOT NULL
{% endset %}

{% set results = run_query(sql) %}
{% if execute %}
  {% set accounts = results.columns[0].values() %}
{% endif %}

WITH base AS (
    SELECT *,
           to_char(date, 'YYYY-MM') as year_month
    FROM {{ ref('reporting__fact_transactions') }}
),
tx_counts AS (
    SELECT
        year_month,
        account_foreign_key,
        COUNT(*) AS tx_count
    FROM base
    GROUP BY 1, 2
)
SELECT
    year_month,
    {% for account in accounts %}
      MAX(CASE WHEN lower(account_foreign_key) = lower('{{ account }}') THEN tx_count ELSE NULL END) AS "{{ account }}"
      {% if not loop.last %}, {% endif %}
    {% endfor %}
FROM tx_counts
GROUP BY year_month
ORDER BY year_month
