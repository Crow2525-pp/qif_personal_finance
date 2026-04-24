{{ config(materialized='table') }}

WITH grocery_transactions AS (
    SELECT
        ft.transaction_date,
        CASE WHEN ft.transaction_amount < 0 THEN -ft.transaction_amount ELSE ft.transaction_amount END AS abs_amount,
        ft.transaction_memo,
        ft.transaction_description,
        dc.store AS grocery_store,
        dc.payment_frequency,
        DATE_TRUNC('month', ft.transaction_date) AS year_month
    FROM {{ ref('fct_transactions') }} ft
    LEFT JOIN {{ ref('dim_categories') }} dc ON ft.category_key = dc.category_key
    WHERE
        ft.transaction_amount < 0
        AND dc.subcategory = 'Groceries'
        AND dc.store IN ('Coles', 'Woolworths', 'Gaskos')
),

grocery_orders AS (
    -- One row per store per day (shopping trip proxy).
    SELECT
        transaction_date::date AS order_date,
        DATE_TRUNC('month', transaction_date) AS year_month,
        grocery_store,
        MAX(payment_frequency) AS payment_frequency,
        SUM(abs_amount) AS order_amount
    FROM grocery_transactions
    GROUP BY transaction_date::date, DATE_TRUNC('month', transaction_date), grocery_store
),

-- Per-store median basket size computed over all history.
-- Orders at or above the median are "Main Shop"; below are "Top-up".
-- Using the store's own median makes the threshold self-calibrating and avoids
-- any hardcoded dollar amounts.
store_medians AS (
    SELECT
        grocery_store,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY order_amount) AS median_basket
    FROM grocery_orders
    GROUP BY grocery_store
),

classified_orders AS (
    SELECT
        go.order_date,
        go.year_month,
        go.grocery_store,
        go.payment_frequency,
        go.order_amount,
        sm.median_basket,
        CASE
            WHEN go.order_amount >= sm.median_basket THEN 'Main Shop'
            ELSE 'Top-up'
        END AS shop_type
    FROM grocery_orders go
    JOIN store_medians sm ON go.grocery_store = sm.grocery_store
),

period_stats AS (
    SELECT
        year_month,
        grocery_store,
        COUNT(*) AS order_count,
        ROUND(AVG(order_amount)::numeric, 2) AS average_order_value,
        MAX(order_amount) AS largest_order_value,
        MIN(order_amount) AS smallest_order_value,
        SUM(order_amount) AS total_spend
    FROM classified_orders
    GROUP BY year_month, grocery_store
),

shop_type_split AS (
    SELECT
        year_month,
        grocery_store,
        shop_type,
        COUNT(*) AS order_count,
        SUM(order_amount) AS category_spend,
        ROUND(AVG(order_amount)::numeric, 2) AS avg_amount
    FROM classified_orders
    GROUP BY year_month, grocery_store, shop_type
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
    (SELECT MAX(payment_frequency) FROM classified_orders co WHERE co.year_month = bst.year_month AND co.grocery_store = bst.grocery_store) AS payment_frequency,
    (SELECT MAX(median_basket) FROM classified_orders co WHERE co.year_month = bst.year_month AND co.grocery_store = bst.grocery_store) AS median_basket_threshold,
    bst.order_count,
    bst.average_order_value,
    (SELECT largest_order_value FROM period_stats ps WHERE ps.year_month = bst.year_month AND ps.grocery_store = bst.grocery_store) AS largest_order_value,
    bst.previous_month_aov,
    bst.aov_mom_change_percent,
    bst.same_month_last_year_orders,
    (SELECT SUM(CASE WHEN st.shop_type = 'Main Shop' THEN st.category_spend ELSE 0 END)
     FROM shop_type_split st WHERE st.year_month = bst.year_month AND st.grocery_store = bst.grocery_store) AS main_shop_spend,
    (SELECT SUM(CASE WHEN st.shop_type = 'Top-up' THEN st.category_spend ELSE 0 END)
     FROM shop_type_split st WHERE st.year_month = bst.year_month AND st.grocery_store = bst.grocery_store) AS topup_spend,
    (SELECT SUM(CASE WHEN st.shop_type = 'Main Shop' THEN st.order_count ELSE 0 END)
     FROM shop_type_split st WHERE st.year_month = bst.year_month AND st.grocery_store = bst.grocery_store) AS main_shop_count,
    (SELECT SUM(CASE WHEN st.shop_type = 'Top-up' THEN st.order_count ELSE 0 END)
     FROM shop_type_split st WHERE st.year_month = bst.year_month AND st.grocery_store = bst.grocery_store) AS topup_count,
    (SELECT total_spend FROM period_stats ps WHERE ps.year_month = bst.year_month AND ps.grocery_store = bst.grocery_store) AS total_monthly_spend
FROM basket_size_trend bst
ORDER BY year_month DESC, grocery_store
