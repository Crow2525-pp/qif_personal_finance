WITH final AS (
    SELECT
        ROUND(SUM(ABS(ft.transaction_amount))::NUMERIC, 2) AS amount,
        dc.level_2_subcategory AS subcategory
    FROM {{ ref('fct_transactions_enhanced') }} AS ft
    LEFT JOIN {{ ref('dim_categories_enhanced') }} AS dc
      ON ft.category_key = dc.category_key
    WHERE
        ft.transaction_amount < 0
        AND NOT COALESCE(ft.is_internal_transfer, FALSE)
        AND UPPER(dc.level_1_category) != 'MORTGAGE'
        AND ft.transaction_date >= CURRENT_DATE - INTERVAL '12 month'
    GROUP BY dc.level_2_subcategory
)

SELECT * FROM final
ORDER BY amount DESC
