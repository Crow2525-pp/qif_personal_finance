{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['period_date'], 'unique': false},
      {'columns': ['driver_type'], 'unique': false}
    ]
  )
}}

WITH recent_outflows AS (
  SELECT 
    TO_CHAR(ft.transaction_date, 'YYYY-MM') AS year_month,
    TO_DATE(TO_CHAR(ft.transaction_date, 'YYYY-MM') || '-01', 'YYYY-MM-DD') AS period_date,
    ft.transaction_date,
    ft.transaction_memo,
    ft.transaction_description,
    ABS(ft.transaction_amount) AS amount,
    
    -- Account and category context
    da.account_name,
    dc.level_1_category,
    dc.level_2_subcategory,
    dc.level_3_store,
    
    -- Grouping for analysis
    CASE 
      WHEN dc.level_1_category IN ('Food & Drink') THEN 'Food & Dining'
      WHEN dc.level_1_category IN ('Household & Services') THEN 'Household & Utilities'
      WHEN dc.level_1_category IN ('Transportation') THEN 'Transportation'
      WHEN dc.level_1_category IN ('Family & Kids') THEN 'Family & Kids'
      WHEN dc.level_1_category IN ('Mortgage') THEN 'Housing & Mortgage'
      WHEN dc.level_1_category IN ('Shopping') THEN 'Shopping & Retail'
      WHEN dc.level_1_category IN ('Health & Fitness') THEN 'Health & Wellness'
      WHEN dc.level_1_category IN ('Entertainment') THEN 'Entertainment'
      ELSE COALESCE(dc.level_1_category, 'Uncategorized')
    END AS expense_category
    
  FROM {{ ref('fct_transactions') }} ft
  LEFT JOIN {{ ref('dim_accounts') }} da
    ON ft.account_key = da.account_key
  LEFT JOIN {{ ref('dim_categories') }} dc
    ON ft.category_key = dc.category_key
  WHERE ft.transaction_amount < 0  -- Only outflows
    AND NOT COALESCE(ft.is_internal_transfer, FALSE)  -- Exclude internal transfers
    AND ft.transaction_date >= CURRENT_DATE - INTERVAL '12 months'  -- Last year
),

-- Top individual transactions by month
top_transactions_ranked AS (
  SELECT 
    'Individual Transaction' AS driver_type,
    period_date,
    year_month,
    expense_category AS category,
    transaction_memo AS description,
    account_name,
    amount,
    transaction_date,
    ROW_NUMBER() OVER (PARTITION BY period_date ORDER BY amount DESC) AS rank_in_month
  FROM recent_outflows
),

top_transactions AS (
  SELECT * 
  FROM top_transactions_ranked
  WHERE rank_in_month <= 10  -- Top 10 per month
),

-- Top recurring expenses (by merchant/subcategory)
recurring_expenses_ranked AS (
  SELECT 
    'Recurring Expense' AS driver_type,
    period_date,
    year_month,
    expense_category AS category,
    COALESCE(level_2_subcategory, level_3_store, 'Unknown Merchant') AS description,
    STRING_AGG(DISTINCT account_name, ', ') AS account_name,
    SUM(amount) AS amount,
    MAX(transaction_date) AS transaction_date,
    COUNT(*) AS transaction_count,
    AVG(amount) AS avg_transaction_amount,
    ROW_NUMBER() OVER (PARTITION BY period_date ORDER BY SUM(amount) DESC) AS rank_in_month
  FROM recent_outflows
  WHERE level_2_subcategory IS NOT NULL 
     OR level_3_store IS NOT NULL
  GROUP BY period_date, year_month, expense_category, 
           COALESCE(level_2_subcategory, level_3_store, 'Unknown Merchant')
  HAVING COUNT(*) >= 2  -- At least 2 transactions to be considered recurring
),

recurring_expenses AS (
  SELECT * 
  FROM recurring_expenses_ranked
  WHERE rank_in_month <= 10  -- Top 10 per month
),

-- Top expense categories by month
category_totals_ranked AS (
  SELECT 
    'Category Total' AS driver_type,
    period_date,
    year_month,
    expense_category AS category,
    expense_category AS description,
    'Multiple Accounts' AS account_name,
    SUM(amount) AS amount,
    MAX(transaction_date) AS transaction_date,
    COUNT(*) AS transaction_count,
    AVG(amount) AS avg_transaction_amount,
    ROW_NUMBER() OVER (PARTITION BY period_date ORDER BY SUM(amount) DESC) AS rank_in_month
  FROM recent_outflows
  GROUP BY period_date, year_month, expense_category
),

category_totals AS (
  SELECT * 
  FROM category_totals_ranked
  WHERE rank_in_month <= 8  -- Top 8 categories per month
),

-- Unusual spikes (transactions significantly higher than category average)
unusual_spikes_ranked AS (
  WITH category_stats AS (
    SELECT 
      expense_category,
      AVG(amount) AS category_avg_amount,
      STDDEV(amount) AS category_stddev_amount
    FROM recent_outflows
    GROUP BY expense_category
  )
  SELECT 
    'Unusual Spike' AS driver_type,
    ro.period_date,
    ro.year_month,
    ro.expense_category AS category,
    CONCAT(ro.transaction_memo, ' (', ROUND((ro.amount / cs.category_avg_amount)::NUMERIC, 1), 'x avg)') AS description,
    ro.account_name,
    ro.amount,
    ro.transaction_date,
    1 AS transaction_count,
    ro.amount AS avg_transaction_amount,
    ROW_NUMBER() OVER (PARTITION BY ro.period_date ORDER BY (ro.amount / cs.category_avg_amount) DESC) AS rank_in_month
  FROM recent_outflows ro
  JOIN category_stats cs
    ON ro.expense_category = cs.expense_category
  WHERE ro.amount > cs.category_avg_amount + (2 * cs.category_stddev_amount)  -- 2 standard deviations above mean
    AND cs.category_avg_amount > 0
),

unusual_spikes AS (
  SELECT * 
  FROM unusual_spikes_ranked
  WHERE rank_in_month <= 5  -- Top 5 spikes per month
),

-- Combine all driver types
all_drivers AS (
  SELECT 
    driver_type,
    period_date,
    year_month,
    category,
    description,
    account_name,
    amount,
    transaction_date,
    1 AS transaction_count,
    amount AS avg_transaction_amount,
    rank_in_month
  FROM top_transactions
  
  UNION ALL
  
  SELECT 
    driver_type,
    period_date,
    year_month,
    category,
    description,
    account_name,
    amount,
    transaction_date,
    transaction_count,
    avg_transaction_amount,
    rank_in_month
  FROM recurring_expenses
  
  UNION ALL
  
  SELECT 
    driver_type,
    period_date,
    year_month,
    category,
    description,
    account_name,
    amount,
    transaction_date,
    transaction_count,
    avg_transaction_amount,
    rank_in_month
  FROM category_totals
  
  UNION ALL
  
  SELECT 
    driver_type,
    period_date,
    year_month,
    category,
    description,
    account_name,
    amount,
    transaction_date,
    transaction_count,
    avg_transaction_amount,
    rank_in_month
  FROM unusual_spikes
),

-- Add monthly context
monthly_totals AS (
  SELECT 
    period_date,
    SUM(amount) AS monthly_total_outflows,
    COUNT(*) AS monthly_total_transactions
  FROM recent_outflows
  GROUP BY period_date
),

-- Final enrichment
final AS (
  SELECT 
    ad.*,
    mt.monthly_total_outflows,
    mt.monthly_total_transactions,
    
    -- Calculate percentage of monthly total
    CASE 
      WHEN mt.monthly_total_outflows > 0 
      THEN (ad.amount / mt.monthly_total_outflows) * 100
      ELSE 0 
    END AS pct_of_monthly_outflows,
    
    -- Driver impact classification
    CASE 
      WHEN ad.amount > 5000 THEN 'High Impact'
      WHEN ad.amount > 1000 THEN 'Medium Impact'
      WHEN ad.amount > 100 THEN 'Low Impact'
      ELSE 'Minimal Impact'
    END AS impact_level,
    
    -- Actionability score
    CASE 
      WHEN driver_type = 'Unusual Spike' THEN 'Review & Investigate'
      WHEN driver_type = 'Individual Transaction' AND amount > 2000 THEN 'Review & Validate'
      WHEN driver_type = 'Recurring Expense' AND transaction_count > 10 THEN 'Optimize & Negotiate'
      WHEN driver_type = 'Category Total' AND rank_in_month <= 3 THEN 'Budget Review'
      ELSE 'Monitor'
    END AS recommended_action,
    
    CURRENT_TIMESTAMP AS report_generated_at
    
  FROM all_drivers ad
  LEFT JOIN monthly_totals mt
    ON ad.period_date = mt.period_date
)

SELECT *
FROM final
ORDER BY period_date DESC, amount DESC, driver_type, rank_in_month