WITH filtered_data AS (
    SELECT
        TO_CHAR(ft.transaction_date, 'Mon-YYYY') AS year_month,
        ft.transaction_memo AS memo,
        SUM({{ metric_interest_payment('ft', 'dc') }}) AS amount
    FROM {{ ref('fct_transactions_enhanced') }} AS ft
    LEFT JOIN {{ ref('dim_categories_enhanced') }} AS dc
      ON ft.category_key = dc.category_key
    WHERE ft.transaction_date >= (DATE_TRUNC('year', CURRENT_DATE - INTERVAL '1 year'))::date
    GROUP BY 1, 2
)
SELECT 
    REPLACE(REPLACE(memo, '''', ''), ' ', '_') AS memo,
    SUM(amount) AS amount
FROM filtered_data
WHERE amount > 0
GROUP BY 1
ORDER BY amount DESC
LIMIT 50
