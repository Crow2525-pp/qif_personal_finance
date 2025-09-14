WITH final AS (
    SELECT
        ROUND(SUM({{ metric_expense(exclude_mortgage=true, table_alias='ft', category_alias='dc') }})::NUMERIC, 2) AS amount,
        dc.level_2_subcategory AS subcategory
    FROM {{ ref('fct_transactions_enhanced') }} AS ft
    LEFT JOIN {{ ref('dim_categories_enhanced') }} AS dc
      ON ft.category_key = dc.category_key
    WHERE ft.transaction_date >= CURRENT_DATE - INTERVAL '12 month'
    GROUP BY dc.level_2_subcategory
)

SELECT * FROM final
ORDER BY amount DESC
