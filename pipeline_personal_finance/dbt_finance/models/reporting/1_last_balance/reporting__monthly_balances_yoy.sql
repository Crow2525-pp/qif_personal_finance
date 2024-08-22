-- models/monthly_balances.sql

{% set year_query  %}
    SELECT DISTINCT EXTRACT(YEAR FROM TO_DATE(year_month, 'YYYY-MM')) AS year
    FROM {{ ref("reporting__last_balance_monthly") }}
    order by EXTRACT(YEAR FROM TO_DATE(year_month, 'YYYY-MM')) asc
{% endset %}

{% set results = run_query(year_query) %}

{% if execute %}
  {% if results and results.columns is defined %}
    {% set year_list = results.columns[0].values() %}
  {% else %}
    {% set year_list = [] %}
  {% endif %}
{% endif %}

SELECT 
    EXTRACT(MONTH FROM TO_DATE(year_month, 'YYYY-MM')) AS month,
    {% for year in year_list %}
        SUM(CASE WHEN EXTRACT(YEAR FROM TO_DATE(year_month, 'YYYY-MM')) = {{ year }} THEN latest_balance ELSE NULL END) AS "{{ year }}"
        {% if not loop.last %}, {% endif %}
    {% endfor %}
FROM 
    {{ ref("reporting__last_balance_monthly") }}
WHERE
    latest_balance IS NOT NULL
GROUP BY
    1
ORDER BY
    1
