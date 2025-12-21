{{ config(materialized='table') }}

WITH grocery_transactions AS (
    SELECT
        ft.date,
        ft.amount,
        ft.memo,
        dc.category,
        dc.subcategory,
        dc.store,
        da.account_name,
        DATE_TRUNC('month', ft.date) AS year_month
    FROM {{ ref('fct_transactions') }} ft
    LEFT JOIN {{ ref('dim_categorise_transaction') }} dc ON ft.category_foreign_key = dc.category_foreign_key
    LEFT JOIN {{ ref('dim_account') }} da ON ft.account_foreign_key = da.origin_key
    WHERE
        ft.amount < 0  -- Only expenses (negative amounts)
        AND (
            LOWER(ft.memo) LIKE '%coles%'
            OR LOWER(ft.memo) LIKE '%woolworths%'
            OR LOWER(ft.memo) LIKE '%woolies%'
            OR LOWER(ft.memo) LIKE '%gaskos%'
            OR LOWER(ft.memo) LIKE '%gascos%'
        )
),

grocery_store_mapping AS (
    SELECT
        *,
        CASE
            WHEN LOWER(memo) LIKE '%coles%' THEN 'Coles'
            WHEN LOWER(memo) LIKE '%woolworths%' OR LOWER(memo) LIKE '%woolies%' THEN 'Woolworths'
            WHEN LOWER(memo) LIKE '%gaskos%' OR LOWER(memo) LIKE '%gascos%' THEN 'Gaskos'
            ELSE 'Other'
        END AS grocery_store
    FROM grocery_transactions
),

monthly_spending AS (
    SELECT
        year_month,
        grocery_store,
        ABS(SUM(amount)) AS monthly_spend,
        COUNT(*) AS transaction_count,
        AVG(ABS(amount)) AS avg_transaction_size
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