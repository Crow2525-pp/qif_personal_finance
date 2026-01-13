{{ config(materialized='table') }}

WITH grocery_transactions AS (
    SELECT
        ft.transaction_date,
        ft.transaction_amount,
        ft.transaction_memo,
        dc.category,
        dc.subcategory,
        dc.store,
        da.account_name,
        DATE_TRUNC('month', ft.transaction_date) AS year_month
    FROM {{ ref('fct_transactions') }} ft
    LEFT JOIN {{ ref('dim_categories') }} dc ON ft.category_key = dc.category_key
    LEFT JOIN {{ ref('dim_accounts') }} da ON ft.account_key = da.account_key
    WHERE
        ft.transaction_amount < 0  -- Only expenses (negative amounts)
        AND (
            LOWER(ft.transaction_memo) LIKE '%coles%'
            OR LOWER(ft.transaction_memo) LIKE '%woolworths%'
            OR LOWER(ft.transaction_memo) LIKE '%woolies%'
            OR LOWER(ft.transaction_memo) LIKE '%gaskos%'
            OR LOWER(ft.transaction_memo) LIKE '%gascos%'
        )
),

grocery_store_mapping AS (
    SELECT
        *,
        CASE
            WHEN LOWER(transaction_memo) LIKE '%coles%' THEN 'Coles'
            WHEN LOWER(transaction_memo) LIKE '%woolworths%' OR LOWER(transaction_memo) LIKE '%woolies%' THEN 'Woolworths'
            WHEN LOWER(transaction_memo) LIKE '%gaskos%' OR LOWER(transaction_memo) LIKE '%gascos%' THEN 'Gaskos'
            ELSE 'Other'
        END AS grocery_store
    FROM grocery_transactions
),

monthly_spending AS (
    SELECT
        year_month,
        grocery_store,
        ABS(SUM(transaction_amount)) AS monthly_spend,
        COUNT(*) AS transaction_count,
        AVG(ABS(transaction_amount)) AS avg_transaction_size
    FROM grocery_store_mapping
    GROUP BY year_month, grocery_store
),

monthly_totals AS (
    SELECT
        year_month,
        SUM(monthly_spend) AS total_monthly_spend,
        SUM(transaction_count) AS total_transaction_count
    FROM monthly_spending
    GROUP BY year_month
),

store_percentages AS (
    SELECT
        ms.*,
        mt.total_monthly_spend,
        mt.total_transaction_count,
        ROUND((ms.monthly_spend / NULLIF(mt.total_monthly_spend, 0)) * 100, 1) AS percentage_of_total
    FROM monthly_spending ms
    LEFT JOIN monthly_totals mt ON ms.year_month = mt.year_month
)

SELECT
    year_month,
    grocery_store,
    monthly_spend,
    transaction_count,
    avg_transaction_size,
    total_monthly_spend,
    total_transaction_count,
    percentage_of_total
FROM store_percentages
ORDER BY year_month DESC, monthly_spend DESC