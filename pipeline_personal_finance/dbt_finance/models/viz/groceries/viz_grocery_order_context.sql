{{ config(materialized='table') }}

WITH grocery_transactions AS (
    SELECT
        ft.transaction_date,
        CASE WHEN ft.transaction_amount < 0 THEN -ft.transaction_amount ELSE ft.transaction_amount END AS abs_amount,
        ft.transaction_memo,
        CASE
            WHEN LOWER(ft.transaction_memo) LIKE '%coles%' THEN 'Coles'
            WHEN LOWER(ft.transaction_memo) LIKE '%woolworths%' OR LOWER(ft.transaction_memo) LIKE '%woolies%' THEN 'Woolworths'
            WHEN LOWER(ft.transaction_memo) LIKE '%gaskos%' OR LOWER(ft.transaction_memo) LIKE '%gascos%' THEN 'Gaskos'
            ELSE 'Other'
        END AS grocery_store,
        -- Grocery subscription/recurring detection (e.g., home delivery subscriptions)
        CASE
            WHEN LOWER(ft.transaction_memo) LIKE '%subscription%'
                OR LOWER(ft.transaction_memo) LIKE '%recurring%'
                OR LOWER(ft.transaction_memo) LIKE '%delivery%'
            THEN 'Subscription/Recurring'
            ELSE 'One-Off Purchase'
        END AS purchase_type,
        DATE_TRUNC('month', ft.transaction_date) AS year_month
    FROM {{ ref('fct_transactions') }} ft
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

grocery_orders AS (
    SELECT
        transaction_date::date AS order_date,
        DATE_TRUNC('month', transaction_date) AS year_month,
        grocery_store,
        purchase_type,
        SUM(abs_amount) AS order_amount
    FROM grocery_transactions
    GROUP BY transaction_date::date, DATE_TRUNC('month', transaction_date), grocery_store, purchase_type
),

period_stats AS (
    SELECT
        year_month,
        grocery_store,
        COUNT(*) AS order_count,
        ROUND(AVG(order_amount), 2) AS average_order_value,
        MAX(order_amount) AS largest_order_value,
        MIN(order_amount) AS smallest_order_value,
        SUM(order_amount) AS total_spend
    FROM grocery_orders
    GROUP BY year_month, grocery_store
),

purchase_type_split AS (
    SELECT
        year_month,
        grocery_store,
        purchase_type,
        COUNT(*) AS order_count,
        SUM(order_amount) AS category_spend,
        ROUND(AVG(order_amount), 2) AS avg_amount
    FROM grocery_orders
    GROUP BY year_month, grocery_store, purchase_type
),

basket_size_trend AS (
    SELECT
        year_month,
        grocery_store,
        order_count,
        average_order_value,
        LAG(average_order_value, 1) OVER (PARTITION BY grocery_store ORDER BY year_month) AS previous_month_aov,
        CASE
            WHEN LAG(average_order_value, 1) OVER (PARTITION BY grocery_store ORDER BY year_month) > 0 THEN
                ROUND(((average_order_value - LAG(average_order_value, 1) OVER (PARTITION BY grocery_store ORDER BY year_month)) /
                       LAG(average_order_value, 1) OVER (PARTITION BY grocery_store ORDER BY year_month)) * 100, 1)
            ELSE NULL
        END AS aov_mom_change_percent,
        LAG(order_count, 12) OVER (PARTITION BY grocery_store ORDER BY year_month) AS same_month_last_year_orders
    FROM period_stats
)

SELECT
    bst.year_month,
    bst.grocery_store,
    bst.order_count,
    bst.average_order_value,
    (SELECT largest_order_value FROM period_stats ps WHERE ps.year_month = bst.year_month AND ps.grocery_store = bst.grocery_store) AS largest_order_value,
    bst.previous_month_aov,
    bst.aov_mom_change_percent,
    bst.same_month_last_year_orders,
    (SELECT SUM(CASE WHEN pt.purchase_type = 'Subscription/Recurring' THEN pt.category_spend ELSE 0 END)
     FROM purchase_type_split pt WHERE pt.year_month = bst.year_month AND pt.grocery_store = bst.grocery_store) AS recurring_spend,
    (SELECT SUM(CASE WHEN pt.purchase_type = 'One-Off Purchase' THEN pt.category_spend ELSE 0 END)
     FROM purchase_type_split pt WHERE pt.year_month = bst.year_month AND pt.grocery_store = bst.grocery_store) AS oneoff_spend,
    (SELECT SUM(CASE WHEN pt.purchase_type = 'Subscription/Recurring' THEN pt.order_count ELSE 0 END)
     FROM purchase_type_split pt WHERE pt.year_month = bst.year_month AND pt.grocery_store = bst.grocery_store) AS recurring_count,
    (SELECT SUM(CASE WHEN pt.purchase_type = 'One-Off Purchase' THEN pt.order_count ELSE 0 END)
     FROM purchase_type_split pt WHERE pt.year_month = bst.year_month AND pt.grocery_store = bst.grocery_store) AS oneoff_count,
    (SELECT total_spend FROM period_stats ps WHERE ps.year_month = bst.year_month AND ps.grocery_store = bst.grocery_store) AS total_monthly_spend
FROM basket_size_trend bst
ORDER BY year_month DESC, grocery_store
