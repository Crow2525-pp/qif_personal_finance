
{% set sql %}
  SELECT DISTINCT lower(origin_key) as origin_key
  FROM {{ ref('dim_account') }}
  WHERE origin_key IS NOT NULL
{% endset %}

{% set results = run_query(sql) %}
{% if execute %}
  {% set accounts = results.columns[0].values() %}
{% endif %}

WITH accounts_as_columns AS (
    SELECT
        year_month,
        account_foreign_key,
        {% for account in accounts %}
          MAX(CASE WHEN upper(account_foreign_key) = upper('{{ account }}') THEN latest_balance ELSE NULL END) AS "{{ account }}"
          {% if not loop.last %}, {% endif %}
        {% endfor %}
    FROM
        {{ ref("reporting__periodic_snapshot_yyyymm_balance") }}
    GROUP BY
        1,2
    ORDER BY
        1,2
)
SELECT
    year_month,
    account_foreign_key,
    {% for account in accounts %}
      "{{ account }}"
      {% if not loop.last %}, {% endif %}
    {% endfor %}
FROM
    accounts_as_columns

WHERE 
    {% for account in accounts %}
    COALESCE("{{ account }}", 0) != 0
    {% if not loop.last %} OR {% endif %}
    {% endfor %}
