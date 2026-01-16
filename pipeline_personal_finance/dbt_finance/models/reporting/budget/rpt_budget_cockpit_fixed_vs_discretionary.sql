{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['budget_year_month'], 'unique': false}
    ]
  )
}}

WITH category_classification AS (
  SELECT
    category_key,
    level_1_category,
    level_2_subcategory,
    -- Define fixed vs discretionary based on category
    CASE
      WHEN level_1_category IN ('Mortgage', 'Bank Transaction') THEN 'Fixed'
      WHEN level_1_category IN ('Household & Services', 'Insurance') THEN 'Fixed'
      WHEN level_1_category = 'Utilities' THEN 'Fixed'
      WHEN level_1_category IN ('Food & Drink', 'Family & Kids', 'Entertainment', 'Shopping', 'Hobbies', 'Travel') THEN 'Discretionary'
      WHEN level_1_category IN ('Healthcare', 'Personal Care') THEN 'Mixed'
      WHEN level_1_category IN ('Uncategorized', 'Unclassified') THEN 'Uncategorized'
      ELSE 'Discretionary'
    END as spending_type
  FROM {{ ref('dim_categories') }}
  WHERE is_internal_transfer = false AND category_type = 'Expense'
),

monthly_spending_classified AS (
  SELECT
    ft.transaction_year,
    ft.transaction_month,
    ft.transaction_year || '-' || LPAD(ft.transaction_month::TEXT, 2, '0') as budget_year_month,
    cc.spending_type,
    cc.level_1_category,
    cc.level_2_subcategory,
    SUM(CASE WHEN ft.transaction_amount < 0 THEN ABS(ft.transaction_amount) ELSE 0 END) as spending_amount,
    COUNT(*) as transaction_count
  FROM {{ ref('fct_transactions') }} ft
  INNER JOIN category_classification cc ON ft.category_key = cc.category_key
  GROUP BY ft.transaction_year, ft.transaction_month, budget_year_month, cc.spending_type, cc.level_1_category, cc.level_2_subcategory
),

spending_rollup AS (
  SELECT
    budget_year_month,
    spending_type,
    SUM(spending_amount) as total_spending,
    SUM(transaction_count) as total_transactions,
    AVG(spending_amount / NULLIF(transaction_count, 0)) as avg_transaction_size,
    MAX(spending_amount) as largest_category_spend
  FROM monthly_spending_classified
  GROUP BY budget_year_month, spending_type
),

total_monthly_spending AS (
  SELECT
    budget_year_month,
    SUM(total_spending) as total_monthly_spending
  FROM spending_rollup
  GROUP BY budget_year_month
),

spending_with_variance AS (
  SELECT
    sr.budget_year_month,
    sr.spending_type,
    ROUND(sr.total_spending, 2) as amount,
    sr.total_transactions,
    ROUND(sr.avg_transaction_size, 2) as avg_transaction_size,
    -- Calculate percentage of total spending
    ROUND((sr.total_spending / NULLIF(tms.total_monthly_spending, 0)) * 100, 1) as pct_of_total_spending,
    -- Historical comparison (3-month average)
    ROUND(AVG(sr.total_spending) OVER (
      PARTITION BY sr.spending_type
      ORDER BY sr.budget_year_month
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ), 2) as rolling_3m_avg,
    -- Variance from 3-month average
    ROUND(sr.total_spending - COALESCE(
      AVG(sr.total_spending) OVER (
        PARTITION BY sr.spending_type
        ORDER BY sr.budget_year_month
        ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
      ),
      sr.total_spending
    ), 2) as variance_from_historical_avg
  FROM spending_rollup sr
  INNER JOIN total_monthly_spending tms ON sr.budget_year_month = tms.budget_year_month
),

category_breakdown AS (
  SELECT
    msc.budget_year_month,
    msc.spending_type,
    msc.level_1_category,
    ROUND(SUM(msc.spending_amount), 2) as category_spending,
    SUM(msc.transaction_count) as category_transaction_count,
    ROW_NUMBER() OVER (PARTITION BY msc.budget_year_month, msc.spending_type ORDER BY SUM(msc.spending_amount) DESC) as category_rank
  FROM monthly_spending_classified msc
  GROUP BY msc.budget_year_month, msc.spending_type, msc.level_1_category
)

SELECT
  swr.budget_year_month,
  swr.spending_type,
  swr.amount,
  swr.total_transactions,
  swr.avg_transaction_size,
  swr.pct_of_total_spending,
  swr.rolling_3m_avg,
  swr.variance_from_historical_avg,
  -- Variance assessment
  CASE
    WHEN swr.variance_from_historical_avg > (swr.rolling_3m_avg * 0.15) THEN 'Significantly above'
    WHEN swr.variance_from_historical_avg > (swr.rolling_3m_avg * 0.05) THEN 'Above average'
    WHEN swr.variance_from_historical_avg < (swr.rolling_3m_avg * -0.05) THEN 'Below average'
    ELSE 'In line'
  END as variance_assessment,
  -- Top category in this spending type (for context)
  (SELECT cb.level_1_category FROM category_breakdown cb
   WHERE cb.budget_year_month = swr.budget_year_month
     AND cb.spending_type = swr.spending_type
     AND cb.category_rank = 1 LIMIT 1) as top_category,
  CURRENT_TIMESTAMP as report_generated_at
FROM spending_with_variance swr
ORDER BY swr.budget_year_month DESC,
         CASE WHEN swr.spending_type = 'Fixed' THEN 0 ELSE 1 END,
         swr.amount DESC
