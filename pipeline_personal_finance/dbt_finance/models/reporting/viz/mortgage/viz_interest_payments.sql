-- depends_on: {{ ref('viz_top_memos') }}

WITH filtered_data AS (
    SELECT
        DATE_TRUNC('month', ft.transaction_date)::date AS year_month_date,
        TO_CHAR(ft.transaction_date, 'Mon-YYYY') AS year_month,
        ft.transaction_memo AS memo,
        SUM({{ metric_interest_payment('ft', 'dc') }}) AS amount
    FROM {{ ref('fct_transactions_enhanced') }} AS ft
    LEFT JOIN {{ ref('dim_categories_enhanced') }} AS dc
      ON ft.category_key = dc.category_key
    WHERE ft.transaction_date >= (DATE_TRUNC('year', CURRENT_DATE - INTERVAL '1 year'))::date
    GROUP BY 1, 2, 3
)
SELECT
    fd.year_month_date,
    fd.year_month,
    SUM(fd.amount) AS "INTEREST"
    {# Ensure this compiles when execute is false (e.g., dbt compile) #}
    {% if execute %}
      {% set alias_values = dbt_utils.get_column_values(table=ref('viz_top_memos'), column='memo') %}
    {% else %}
      {% set alias_values = [] %}
    {% endif %}
    {% set cols = alias_values | default([], true) %}
    {% if cols | length > 0 %}
      , {% for alias in cols %}
        SUM(
            CASE 
                WHEN REPLACE(REPLACE(fd.memo, '''', ''), ' ', '_') = '{{ alias }}'
                THEN fd.amount 
                ELSE 0 
            END
        ) AS "{{ alias }}_BREAKDOWN"{% if not loop.last %}, {% endif %}
      {% endfor %}
    {% endif %}
FROM filtered_data AS fd
GROUP BY 1, 2
ORDER BY fd.year_month_date
