{{
  config(
    materialized='table'
  )
}}

WITH current_month_base AS (
  SELECT
    DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month') as analysis_month
),

current_month_outflows AS (
  SELECT
    c.category,
    c.subcategory,
    SUM(ABS(t.transaction_amount)) as total_outflows,
    COUNT(*) as transaction_count,
    AVG(ABS(t.transaction_amount)) as avg_transaction_size,
    MAX(ABS(t.transaction_amount)) as largest_transaction,
    -- Get the memo of the largest transaction
    (ARRAY_AGG(t.transaction_memo ORDER BY ABS(t.transaction_amount) DESC))[1] as largest_transaction_memo
  FROM {{ ref('fct_transactions') }} t
  JOIN {{ ref('dim_categories') }} c ON t.category_key = c.category_key
  CROSS JOIN current_month_base cmb
  WHERE DATE_TRUNC('month', t.transaction_date) = cmb.analysis_month
    AND t.transaction_amount < 0
    AND c.is_internal_transfer = false
  GROUP BY c.category, c.subcategory
),

historical_averages AS (
  SELECT
    c.category,
    c.subcategory,
    AVG(ABS(t.transaction_amount)) as historical_avg_monthly,
    COUNT(DISTINCT DATE_TRUNC('month', t.transaction_date)) as months_of_data
  FROM {{ ref('fct_transactions') }} t
  JOIN {{ ref('dim_categories') }} c ON t.category_key = c.category_key
  CROSS JOIN current_month_base cmb
  WHERE DATE_TRUNC('month', t.transaction_date) < cmb.analysis_month
    AND DATE_TRUNC('month', t.transaction_date) >= cmb.analysis_month - INTERVAL '6 months'
    AND t.transaction_amount < 0
    AND c.is_internal_transfer = false
  GROUP BY c.category, c.subcategory
  HAVING COUNT(DISTINCT DATE_TRUNC('month', t.transaction_date)) >= 2
),

total_outflows_current AS (
  SELECT SUM(total_outflows) as total_monthly_outflows
  FROM current_month_outflows
)

SELECT
  cmo.category,
  cmo.subcategory,
  ROUND(cmo.total_outflows, 2) as current_month_outflows,
  cmo.transaction_count,
  ROUND(cmo.avg_transaction_size, 2) as avg_transaction_size,
  ROUND(cmo.largest_transaction, 2) as largest_transaction,
  cmo.largest_transaction_memo,

  -- Historical comparison
  ROUND(COALESCE(ha.historical_avg_monthly, 0), 2) as historical_6month_avg,
  ROUND(cmo.total_outflows - COALESCE(ha.historical_avg_monthly, 0), 2) as variance_vs_historical,
  CASE
    WHEN ha.historical_avg_monthly > 0
    THEN ROUND(((cmo.total_outflows - ha.historical_avg_monthly) / ha.historical_avg_monthly) * 100, 1)
    ELSE NULL
  END as pct_change_vs_historical,

  -- Percentage of total outflows
  ROUND((cmo.total_outflows / toc.total_monthly_outflows) * 100, 2) as pct_of_total_outflows,

  -- Risk flags
  CASE
    WHEN cmo.category = 'Uncategorized' AND cmo.total_outflows > 500
    THEN 'High Uncategorized Spending'
    WHEN ha.historical_avg_monthly > 0 AND cmo.total_outflows > ha.historical_avg_monthly * 2
    THEN 'Significantly Above Historical Average'
    WHEN cmo.largest_transaction > 1000
    THEN 'Contains Large Transaction'
    WHEN cmo.total_outflows > 1000 AND cmo.transaction_count = 1
    THEN 'Single Large Transaction'
    ELSE 'Normal'
  END as risk_flag

FROM current_month_outflows cmo
LEFT JOIN historical_averages ha ON cmo.category = ha.category AND cmo.subcategory = ha.subcategory
CROSS JOIN total_outflows_current toc
ORDER BY cmo.total_outflows DESC