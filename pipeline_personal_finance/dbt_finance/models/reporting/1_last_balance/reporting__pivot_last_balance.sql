
{% set sql %}
  SELECT DISTINCT lower(account_name)
  FROM {{ ref('reporting__last_balance') }}
  WHERE account_name IS NOT NULL
{% endset %}

{% set results = run_query(sql) %}
{% if execute %}
  {% set accounts = results.columns[0].values() %}
{% endif %}

WITH query AS (
    SELECT
        TO_CHAR(date, 'YYYY-MM') AS year_month,
        {% for account in accounts %}
        MAX(CASE WHEN account_name = '{{ account }}' THEN latest_balance ELSE NULL END) AS "{{ account }}"
        {% if not loop.last %}, {% endif %}
        {% endfor %}
    FROM
        {{ ref("reporting__last_balance") }}
    GROUP BY
        year_month
    ORDER BY
        year_month
)
SELECT
    year_month,
    {% for account in accounts %}
    "{{ account }}"
    {% if not loop.last %}, {% endif %}
    {% endfor %}
FROM
    query
WHERE 
    {% for account in accounts %}
    COALESCE("{{ account }}", 0) != 0
    {% if not loop.last %} OR {% endif %}
    {% endfor %}