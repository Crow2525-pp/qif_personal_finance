{{ config(materialized='table') }}

WITH grocery_analysis AS (
    SELECT * FROM {{ ref('viz_grocery_spending_analysis') }}
),

pivot_stores AS (
    SELECT
        year_month,
        SUM(CASE WHEN grocery_store = 'Coles' THEN monthly_spend ELSE 0 END) AS coles_spend,
        SUM(CASE WHEN grocery_store = 'Woolworths' THEN monthly_spend ELSE 0 END) AS woolworths_spend,
        SUM(CASE WHEN grocery_store = 'Gaskos' THEN monthly_spend ELSE 0 END) AS gaskos_spend,
        SUM(monthly_spend) AS total_grocery_spend,

        SUM(CASE WHEN grocery_store = 'Coles' THEN transaction_count ELSE 0 END) AS coles_transactions,
        SUM(CASE WHEN grocery_store = 'Woolworths' THEN transaction_count ELSE 0 END) AS woolworths_transactions,
        SUM(CASE WHEN grocery_store = 'Gaskos' THEN transaction_count ELSE 0 END) AS gaskos_transactions,
        SUM(transaction_count) AS total_transactions
    FROM grocery_analysis
    GROUP BY year_month
),

trends AS (
    SELECT
        *,
        LAG(total_grocery_spend, 1) OVER (ORDER BY year_month) AS previous_month_total,
        LAG(total_grocery_spend, 12) OVER (ORDER BY year_month) AS same_month_last_year_total,

        CASE
            WHEN LAG(total_grocery_spend, 1) OVER (ORDER BY year_month) > 0 THEN
                ROUND(((total_grocery_spend - LAG(total_grocery_spend, 1) OVER (ORDER BY year_month)) /
                      LAG(total_grocery_spend, 1) OVER (ORDER BY year_month)) * 100, 1)
            ELSE NULL
        END AS mom_growth_percent,

        CASE
            WHEN LAG(total_grocery_spend, 12) OVER (ORDER BY year_month) > 0 THEN
                ROUND(((total_grocery_spend - LAG(total_grocery_spend, 12) OVER (ORDER BY year_month)) /
                      LAG(total_grocery_spend, 12) OVER (ORDER BY year_month)) * 100, 1)
            ELSE NULL
        END AS yoy_growth_percent
    FROM pivot_stores
)

SELECT
    year_month,
    coles_spend,
    woolworths_spend,
    gaskos_spend,
    total_grocery_spend,
    coles_transactions,
    woolworths_transactions,
    gaskos_transactions,
    total_transactions,
    previous_month_total,
    same_month_last_year_total,
    mom_growth_percent,
    yoy_growth_percent,

    -- Calculate store percentages
    CASE WHEN total_grocery_spend > 0 THEN ROUND((coles_spend / total_grocery_spend) * 100, 1) ELSE 0 END AS coles_percentage,
    CASE WHEN total_grocery_spend > 0 THEN ROUND((woolworths_spend / total_grocery_spend) * 100, 1) ELSE 0 END AS woolworths_percentage,
    CASE WHEN total_grocery_spend > 0 THEN ROUND((gaskos_spend / total_grocery_spend) * 100, 1) ELSE 0 END AS gaskos_percentage,

    -- Average transaction sizes
    CASE WHEN coles_transactions > 0 THEN ROUND(coles_spend / coles_transactions, 2) ELSE 0 END AS coles_avg_transaction,
    CASE WHEN woolworths_transactions > 0 THEN ROUND(woolworths_spend / woolworths_transactions, 2) ELSE 0 END AS woolworths_avg_transaction,
    CASE WHEN gaskos_transactions > 0 THEN ROUND(gaskos_spend / gaskos_transactions, 2) ELSE 0 END AS gaskos_avg_transaction,
    CASE WHEN total_transactions > 0 THEN ROUND(total_grocery_spend / total_transactions, 2) ELSE 0 END AS total_avg_transaction

FROM trends
ORDER BY year_month DESC