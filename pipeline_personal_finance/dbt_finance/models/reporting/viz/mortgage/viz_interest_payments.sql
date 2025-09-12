WITH filtered_data AS (
    SELECT
        TO_CHAR(ft.transaction_date, 'Mon-YYYY') AS year_month,
        ft.transaction_memo AS memo,
        SUM(ABS(ft.transaction_amount)) AS amount
    FROM {{ ref('fct_transactions_enhanced') }} AS ft
    LEFT JOIN {{ ref('dim_categories_enhanced') }} AS dc
      ON ft.category_key = dc.category_key
    WHERE
        NOT COALESCE(ft.is_internal_transfer, FALSE)
        AND ft.transaction_amount < 0
        AND UPPER(dc.level_1_category) = 'MORTGAGE'
    GROUP BY 1, 2
)
SELECT
    fd.year_month
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
        ) AS "{{ alias }}"{% if not loop.last %}, {% endif %}
      {% endfor %}
    {% else %}
      , SUM(fd.amount) AS total_amount
    {% endif %}
FROM filtered_data AS fd
WHERE REPLACE(REPLACE(fd.memo, '''', ''), ' ', '_') IN (
    SELECT memo FROM {{ ref('viz_top_memos') }}
)
GROUP BY 1
ORDER BY TO_DATE(fd.year_month, 'Mon-YYYY')
