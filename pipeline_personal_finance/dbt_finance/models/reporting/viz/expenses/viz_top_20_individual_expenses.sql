WITH final AS (
    SELECT
        ft.transaction_date::date,
        ft.transaction_direction,
        dc.level_2_subcategory AS subcategory,
        ft.transaction_memo AS memo,
        {{ metric_expense(exclude_mortgage=true, table_alias='ft', category_alias='dc') }} AS amount
    FROM {{ ref('fct_transactions_enhanced') }} AS ft
    LEFT JOIN {{ ref('dim_categories_enhanced') }} AS dc
      ON ft.category_key = dc.category_key
    WHERE ft.transaction_date >= CURRENT_DATE - INTERVAL '12 month'
)

SELECT * FROM final
ORDER BY amount DESC
LIMIT 20
