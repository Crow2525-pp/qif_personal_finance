{% set sql %}
  SELECT
    DISTINCT lower(origin_key) AS origin_key
  FROM {{ ref('dim_account') }}
  WHERE origin_key IS NOT NULL
{% endset %}

{% set results = run_query(sql) %}
{% if execute %}
  {% set accounts = results.columns[0].values() %}
{% endif %}

WITH

  current_balance AS (
    SELECT *
    FROM {{ ref("viz_balance_by_year_month") }}
  ),

  previous_balance AS (
    SELECT
      period_date,
      (period_date + INTERVAL '1 month')::date AS next_period_date,
      year_month,
      {% for account in accounts %}
        "{{ account }}"
        {% if not loop.last %}, {% endif %}
      {% endfor %}
    FROM {{ ref("viz_balance_by_year_month") }}
  ),

  monthly_differences AS (
    SELECT
      cb.period_date,
      cb.year_month,
      {% for account in accounts %}
        cb."{{ account }}" - COALESCE(pb."{{ account }}", 0) AS "{{ account }}_MoM"
        {% if not loop.last %}, {% endif %}
      {% endfor %}
    FROM current_balance AS cb
    LEFT JOIN previous_balance AS pb
      ON cb.period_date = pb.next_period_date
  )

SELECT *
FROM monthly_differences
ORDER BY period_date ASC
