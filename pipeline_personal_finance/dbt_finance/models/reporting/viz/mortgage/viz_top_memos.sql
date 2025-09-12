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
    REPLACE(REPLACE(memo, '''', ''), ' ', '_') AS memo,
    SUM(amount) AS amount
FROM filtered_data
GROUP BY 1
ORDER BY amount DESC
