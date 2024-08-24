
{% set sql %}
  SELECT DISTINCT EXTRACT(YEAR from date)
  FROM {{ ref('reporting__last_balance') }}
  WHERE date IS NOT NULL
{% endset %}

{% set results = run_query(sql) %}
{% if execute %}
  {% set years = results.columns[0].values() %}
{% endif %}

WITH query AS (
    SELECT
        --date, 
        TO_CHAR(date, 'YYYY-MM') AS year_month, 
        SUM(latest_balance) AS latest_balance
    FROM
        {{ ref("reporting__last_balance") }}
    GROUP BY
        1
    ORDER BY
        1
)
SELECT
    *
FROM
    query