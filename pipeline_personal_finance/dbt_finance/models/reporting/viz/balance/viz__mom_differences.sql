{% set sql %}
  SELECT DISTINCT lower(origin_key) as origin_key
  FROM {{ ref('dim_account') }}
  WHERE origin_key IS NOT NULL
{% endset %}

{% set results = run_query(sql) %}
{% if execute %}
  {% set accounts = results.columns[0].values() %}
{% endif %}

WITH monthly_differences AS (
    SELECT
        a.year_month,
        a.account_foreign_key,
        {% for account in accounts %}
          a."{{ account }}" - COALESCE(b."{{ account }}", 0) AS "{{ account }}_MoM"
          {% if not loop.last %}, {% endif %}
        {% endfor %}
    FROM 
        {{ ref("viz__balance_by_year_month") }} as a
    LEFT JOIN 
        {{ ref("viz__balance_by_year_month") }} as b 
        ON a.year_month = TO_CHAR(TO_DATE(b.year_month, 'YYYY-MM') - INTERVAL '1 month', 'YYYY-MM')
        and a.account_foreign_key = b.account_foreign_key
)

SELECT 
    *
FROM 
    monthly_differences
ORDER BY 
    year_month ASC
