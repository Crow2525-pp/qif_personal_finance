WITH filtered_data AS (
    SELECT
        TO_CHAR(date, 'Mon-YYYY') AS year_month,
        trans.memo,
        SUM(amount) AS amount
    FROM {{ ref('reporting__fact_transactions') }} AS trans
    LEFT JOIN {{ ref('dim_category') }} AS cat
      ON trans.category_foreign_key = cat.origin_key
    WHERE
        UPPER(cat.internal_indicator) = 'EXTERNAL'
        AND UPPER(trans.amount_type) = 'CREDIT'
        AND UPPER(cat.category) = 'MORTGAGE'
    GROUP BY 1, 2
)
SELECT
    fd.year_month,
    {% set alias_values = dbt_utils.get_column_values(
        table=ref('top_memos'),
        column='memo'
    ) %}
    {% for alias in alias_values %}
        SUM(
            CASE 
                WHEN REPLACE(REPLACE(fd.memo, '''', ''), ' ', '_') = '{{ alias }}'
                THEN fd.amount 
                ELSE 0 
            END
        ) AS "{{ alias }}"{{ "," if not loop.last }}
    {% endfor %}
FROM filtered_data AS fd
WHERE REPLACE(REPLACE(fd.memo, '''', ''), ' ', '_') IN (
    SELECT memo FROM {{ ref('top_memos') }}
)
GROUP BY 1
ORDER BY TO_DATE(fd.year_month, 'Mon-YYYY')
