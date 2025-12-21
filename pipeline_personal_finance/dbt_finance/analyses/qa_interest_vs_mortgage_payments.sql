-- Inspect mortgage transactions to validate interest detection logic
WITH mortgage_tx AS (
    SELECT 
        ft.transaction_date,
        TO_CHAR(ft.transaction_date, 'YYYY-MM') AS year_month,
        ft.transaction_memo,
        ft.transaction_type,
        dc.level_1_category,
        dc.level_2_subcategory,
        dc.level_3_store,
        ft.transaction_amount,
        {{ metric_interest_payment() }} AS interest_amount,
        {{ metric_expense() }} AS expense_amount
    FROM {{ ref('fct_transactions_enhanced') }} ft
    LEFT JOIN {{ ref('dim_categories_enhanced') }} dc
      ON ft.category_key = dc.category_key
    WHERE dc.level_1_category = 'Mortgage'
),
monthly AS (
    SELECT 
        year_month,
        SUM(expense_amount)  AS mortgage_total_paid,
        SUM(interest_amount) AS mortgage_interest_detected,
        SUM(expense_amount) - SUM(interest_amount) AS implied_principal
    FROM mortgage_tx
    GROUP BY year_month
)
SELECT *
FROM monthly
ORDER BY year_month;

