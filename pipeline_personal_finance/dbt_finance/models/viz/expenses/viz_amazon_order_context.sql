{{ config(materialized='table') }}

WITH amazon_transactions AS (
    SELECT
        ft.transaction_date,
        CASE WHEN ft.transaction_amount < 0 THEN -ft.transaction_amount ELSE ft.transaction_amount END AS abs_amount,
        ft.transaction_memo,
        dc.category,
        dc.subcategory,
        DATE_TRUNC('month', ft.transaction_date) AS year_month,
        -- Simple heuristic: Amazon subscriptions/recurring typically have specific keywords
        CASE
            WHEN LOWER(ft.transaction_memo) LIKE '%prime%'
                OR LOWER(ft.transaction_memo) LIKE '%subscribe%'
                OR LOWER(ft.transaction_memo) LIKE '%recurring%'
                OR LOWER(ft.transaction_memo) LIKE '%membership%'
            THEN 'Subscription/Recurring'
            ELSE 'One-Off Purchase'
        END AS purchase_type
    FROM {{ ref('fct_transactions') }} ft
    LEFT JOIN {{ ref('dim_categories') }} dc ON ft.category_key = dc.category_key
    WHERE
        ft.transaction_amount < 0  -- Only expenses (negative amounts)
        AND LOWER(ft.transaction_memo) LIKE '%amazon%'
),

period_stats AS (
    SELECT
        year_month,
        COUNT(DISTINCT transaction_date) AS order_count,
        ROUND(AVG(abs_amount), 2) AS average_order_value,
        MAX(abs_amount) AS largest_order_value,
        MIN(abs_amount) AS smallest_order_value,
        SUM(abs_amount) AS total_spend
    FROM amazon_transactions
    GROUP BY year_month
),

purchase_type_split AS (
    SELECT
        year_month,
        purchase_type,
        COUNT(*) AS transaction_count,
        SUM(abs_amount) AS category_spend,
        ROUND(AVG(abs_amount), 2) AS avg_amount
    FROM amazon_transactions
    GROUP BY year_month, purchase_type
),

basket_size_trend AS (
    SELECT
        year_month,
        order_count,
        average_order_value,
        LAG(average_order_value, 1) OVER (ORDER BY year_month) AS previous_month_aov,
        CASE
            WHEN LAG(average_order_value, 1) OVER (ORDER BY year_month) > 0 THEN
                ROUND(((average_order_value - LAG(average_order_value, 1) OVER (ORDER BY year_month)) /
                       LAG(average_order_value, 1) OVER (ORDER BY year_month)) * 100, 1)
            ELSE NULL
        END AS aov_mom_change_percent,
        LAG(order_count, 12) OVER (ORDER BY year_month) AS same_month_last_year_orders
    FROM period_stats
)

SELECT
    bst.year_month,
    bst.order_count,
    bst.average_order_value,
    (SELECT largest_order_value FROM period_stats ps WHERE ps.year_month = bst.year_month) AS largest_order_value,
    bst.previous_month_aov,
    bst.aov_mom_change_percent,
    bst.same_month_last_year_orders,
    (SELECT SUM(CASE WHEN pt.purchase_type = 'Subscription/Recurring' THEN pt.category_spend ELSE 0 END)
     FROM purchase_type_split pt WHERE pt.year_month = bst.year_month) AS recurring_spend,
    (SELECT SUM(CASE WHEN pt.purchase_type = 'One-Off Purchase' THEN pt.category_spend ELSE 0 END)
     FROM purchase_type_split pt WHERE pt.year_month = bst.year_month) AS oneoff_spend,
    (SELECT SUM(CASE WHEN pt.purchase_type = 'Subscription/Recurring' THEN pt.transaction_count ELSE 0 END)
     FROM purchase_type_split pt WHERE pt.year_month = bst.year_month) AS recurring_count,
    (SELECT SUM(CASE WHEN pt.purchase_type = 'One-Off Purchase' THEN pt.transaction_count ELSE 0 END)
     FROM purchase_type_split pt WHERE pt.year_month = bst.year_month) AS oneoff_count,
    (SELECT total_spend FROM period_stats ps WHERE ps.year_month = bst.year_month) AS total_monthly_spend
FROM basket_size_trend bst
ORDER BY year_month DESC
