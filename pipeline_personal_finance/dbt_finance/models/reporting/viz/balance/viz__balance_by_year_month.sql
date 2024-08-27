
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
        category_foreign_key,
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
    aac.year_month,
    aac.category_foreign_key,
    cat.category,
    cat.subcategory,
    cat.store,
    cat.internal_indicator,
    {% for account in accounts %}
      "{{ account }}"
      {% if not loop.last %}, {% endif %}
    {% endfor %}
FROM
    accounts_as_columns as aac
    left join {{ ref("dim_category") }} as cat
    on aac.category_foreign_key = cat.origin_key

WHERE 
    {% for account in accounts %}
    COALESCE("{{ account }}", 0) != 0
    {% if not loop.last %} OR {% endif %}
    {% endfor %}
