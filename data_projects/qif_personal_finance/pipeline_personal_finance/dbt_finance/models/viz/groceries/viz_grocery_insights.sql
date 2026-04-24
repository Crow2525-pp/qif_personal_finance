{{ config(materialized='table') }}

WITH grocery_base AS (
    SELECT * FROM {{ ref('viz_grocery_spending_analysis') }}
),

year_over_year AS (
    SELECT
        grocery_store,
        year_month,
        EXTRACT(YEAR FROM year_month) AS year,
        EXTRACT(MONTH FROM year_month) AS month,
        monthly_spend,
        LAG(monthly_spend, 12) OVER (
            PARTITION BY grocery_store, EXTRACT(MONTH FROM year_month)
            ORDER BY year_month
        ) AS same_month_last_year,
        percentage_of_total
    FROM grocery_base
),

monthly_trends AS (
    SELECT
        grocery_store,
        year_month,
        monthly_spend,
        LAG(monthly_spend, 1) OVER (
            PARTITION BY grocery_store
            ORDER BY year_month
        ) AS previous_month_spend,
        percentage_of_total
    FROM grocery_base
),

store_rankings AS (
    SELECT
        year_month,
        grocery_store,
        monthly_spend,
        percentage_of_total,
        ROW_NUMBER() OVER (PARTITION BY year_month ORDER BY monthly_spend DESC) AS spending_rank,
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY year_month ORDER BY monthly_spend DESC) = 1 THEN 'Primary Store'
            WHEN ROW_NUMBER() OVER (PARTITION BY year_month ORDER BY monthly_spend DESC) = 2 THEN 'Secondary Store'
            ELSE 'Other Store'
        END AS store_category
    FROM grocery_base
),

insights AS (
    SELECT
        yoy.grocery_store,
        yoy.year_month,
        yoy.monthly_spend,
        yoy.same_month_last_year,
        CASE
            WHEN yoy.same_month_last_year IS NOT NULL AND yoy.same_month_last_year > 0 THEN
                ROUND(((yoy.monthly_spend - yoy.same_month_last_year) / yoy.same_month_last_year) * 100, 1)
            ELSE NULL
        END AS yoy_growth_percent,

        mt.previous_month_spend,
        CASE
            WHEN mt.previous_month_spend IS NOT NULL AND mt.previous_month_spend > 0 THEN
                ROUND(((yoy.monthly_spend - mt.previous_month_spend) / mt.previous_month_spend) * 100, 1)
            ELSE NULL
        END AS mom_growth_percent,

        sr.spending_rank,
        sr.store_category,
        yoy.percentage_of_total
    FROM year_over_year yoy
    LEFT JOIN monthly_trends mt ON yoy.grocery_store = mt.grocery_store AND yoy.year_month = mt.year_month
    LEFT JOIN store_rankings sr ON yoy.grocery_store = sr.grocery_store AND yoy.year_month = sr.year_month
)

SELECT
    grocery_store,
    year_month,
    monthly_spend,
    same_month_last_year,
    yoy_growth_percent,
    previous_month_spend,
    mom_growth_percent,
    spending_rank,
    store_category,
    percentage_of_total,
    CASE
        WHEN ABS(yoy_growth_percent) >= 20 THEN 'High Change'
        WHEN ABS(yoy_growth_percent) >= 10 THEN 'Moderate Change'
        WHEN yoy_growth_percent IS NULL THEN 'No Historical Data'
        ELSE 'Stable'
    END AS yoy_trend_category,
    CASE
        WHEN ABS(mom_growth_percent) >= 25 THEN 'High Volatility'
        WHEN ABS(mom_growth_percent) >= 15 THEN 'Moderate Volatility'
        WHEN mom_growth_percent IS NULL THEN 'No Previous Month'
        ELSE 'Stable'
    END AS mom_trend_category
FROM insights
ORDER BY year_month DESC, monthly_spend DESC