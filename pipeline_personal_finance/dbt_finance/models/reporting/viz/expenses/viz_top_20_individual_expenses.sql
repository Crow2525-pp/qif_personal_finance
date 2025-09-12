WITH final AS (
    SELECT
        ft.transaction_date::date,
        ft.transaction_direction,
        dc.level_2_subcategory AS subcategory,
        ft.transaction_memo AS memo,
        ABS(ft.transaction_amount) AS amount
    FROM {{ ref('fct_transactions_enhanced') }} AS ft
    LEFT JOIN {{ ref('dim_categories_enhanced') }} AS dc
      ON ft.category_key = dc.category_key
    WHERE
        ft.transaction_amount < 0
        AND NOT COALESCE(ft.is_internal_transfer, FALSE)
        AND UPPER(dc.level_1_category) != 'MORTGAGE'
        AND ft.transaction_date >= CURRENT_DATE - INTERVAL '12 month'
)

SELECT * FROM final
ORDER BY amount DESC
LIMIT 20
