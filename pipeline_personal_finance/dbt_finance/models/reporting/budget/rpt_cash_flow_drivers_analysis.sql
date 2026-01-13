{{
  config(
    materialized='table'
  )
}}

WITH monthly_category_outflows AS (
  SELECT
    DATE_TRUNC('month', t.transaction_date) as month_date,
    EXTRACT(YEAR FROM t.transaction_date) as transaction_year,
    EXTRACT(MONTH FROM t.transaction_date) as transaction_month,
    TO_CHAR(DATE_TRUNC('month', t.transaction_date), 'YYYY-MM') as budget_year_month,
    c.category,
    c.subcategory,
    SUM(ABS(t.transaction_amount)) as total_outflows,
    COUNT(*) as transaction_count,
    AVG(ABS(t.transaction_amount)) as avg_transaction_amount,
    MAX(ABS(t.transaction_amount)) as max_transaction_amount,
    MIN(ABS(t.transaction_amount)) as min_transaction_amount
  FROM {{ ref('fct_transactions') }} t
  JOIN {{ ref('dim_categories') }} c ON t.category_key = c.category_key
  WHERE t.transaction_amount < 0
    AND c.is_internal_transfer = false
  GROUP BY
    DATE_TRUNC('month', t.transaction_date),
    EXTRACT(YEAR FROM t.transaction_date),
    EXTRACT(MONTH FROM t.transaction_date),
    TO_CHAR(DATE_TRUNC('month', t.transaction_date), 'YYYY-MM'),
    c.category,
    c.subcategory
),

category_rolling_avg AS (
  SELECT
    month_date,
    budget_year_month,
    category,
    subcategory,
    total_outflows,
    transaction_count,
    avg_transaction_amount,
    max_transaction_amount,
    -- 3-month rolling average for comparison
    AVG(total_outflows) OVER (
      PARTITION BY category, subcategory
      ORDER BY month_date
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) as rolling_3month_avg,
    -- Prior month comparison
    LAG(total_outflows, 1) OVER (
      PARTITION BY category, subcategory
      ORDER BY month_date
    ) as prior_month_amount,
    -- Year over year comparison
    LAG(total_outflows, 12) OVER (
      PARTITION BY category, subcategory
      ORDER BY month_date
    ) as prior_year_amount
  FROM monthly_category_outflows
),

final_analysis AS (
  SELECT
    month_date,
    budget_year_month,
    category,
    subcategory,
    total_outflows,
    transaction_count,
    ROUND(avg_transaction_amount, 2) as avg_transaction_amount,
    max_transaction_amount,
    ROUND(rolling_3month_avg, 2) as rolling_3month_avg,

    -- Month over month variance
    COALESCE(total_outflows - prior_month_amount, 0) as mom_variance,
    CASE
      WHEN prior_month_amount > 0
      THEN ROUND(((total_outflows - prior_month_amount) / prior_month_amount) * 100, 1)
      ELSE NULL
    END as mom_pct_change,

    -- Rolling average variance
    COALESCE(total_outflows - rolling_3month_avg, 0) as rolling_avg_variance,
    CASE
      WHEN rolling_3month_avg > 0
      THEN ROUND(((total_outflows - rolling_3month_avg) / rolling_3month_avg) * 100, 1)
      ELSE NULL
    END as rolling_avg_pct_change,

    -- Year over year variance
    COALESCE(total_outflows - prior_year_amount, 0) as yoy_variance,
    CASE
      WHEN prior_year_amount > 0
      THEN ROUND(((total_outflows - prior_year_amount) / prior_year_amount) * 100, 1)
      ELSE NULL
    END as yoy_pct_change,

    -- Flag unusual spending patterns
    CASE
      WHEN rolling_3month_avg > 0 AND total_outflows > rolling_3month_avg * 1.5
      THEN 'High vs Average'
      WHEN prior_month_amount > 0 AND total_outflows > prior_month_amount * 2
      THEN 'High vs Prior Month'
      WHEN total_outflows > 1000 AND category = 'Uncategorized'
      THEN 'High Uncategorized'
      ELSE 'Normal'
    END as spending_flag

  FROM category_rolling_avg
)

SELECT * FROM final_analysis
ORDER BY month_date DESC, total_outflows DESC