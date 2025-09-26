{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['period_date'], 'unique': false}
    ]
  )
}}

WITH outflows_base AS (
  SELECT 
    TO_CHAR(ft.transaction_date, 'YYYY-MM') AS year_month,
    TO_DATE(TO_CHAR(ft.transaction_date, 'YYYY-MM') || '-01', 'YYYY-MM-DD') AS period_date,
    ft.transaction_date,
    ft.transaction_amount,
    ft.transaction_memo,
    ft.transaction_description,
    
    -- Account context
    da.account_name,
    da.account_type,
    da.account_category,
    
    -- Category breakdown
    dc.level_1_category,
    dc.level_2_subcategory,
    dc.level_3_store,
    dc.category_type,
    
    -- Classification
    CASE 
      WHEN ft.is_internal_transfer THEN 'Internal Transfer'
      WHEN ft.transaction_amount < 0 THEN 'Cash Outflow'
      ELSE 'Other'
    END AS flow_type,
    
    -- Expense categorization for analysis
    CASE
      WHEN dc.level_1_category IN ('Food & Drink') THEN 'Food & Dining'
      WHEN dc.level_1_category IN ('Household & Services') THEN 'Household & Utilities'
      WHEN dc.level_1_category IN ('Transportation', 'Transport') THEN 'Transportation'
      WHEN dc.level_1_category IN ('Family & Kids') THEN 'Family & Kids'
      WHEN dc.level_1_category IN ('Mortgage') THEN 'Housing & Mortgage'
      WHEN dc.level_1_category IN ('Shopping', 'Online Shopping') THEN 'Shopping & Retail'
      WHEN dc.level_1_category IN ('Health & Fitness', 'Health & Beauty') THEN 'Health & Wellness'
      WHEN dc.level_1_category IN ('Entertainment', 'Leisure') THEN 'Entertainment'
      WHEN dc.level_1_category IN ('Travel') THEN 'Travel'
      WHEN dc.level_1_category IN ('Gifts & Charity') THEN 'Gifts & Charity'
      WHEN dc.level_1_category LIKE '%Investment%' THEN 'Investments'
      WHEN dc.level_1_category LIKE '%Insurance%' THEN 'Insurance'
      WHEN dc.level_1_category LIKE '%Tax%' THEN 'Taxes'
      ELSE COALESCE(dc.level_1_category, 'Uncategorized')
    END AS expense_group,
    
    -- Transaction size classification
    CASE 
      WHEN ABS(ft.transaction_amount) >= 5000 THEN 'Large (≥$5000)'
      WHEN ABS(ft.transaction_amount) >= 1000 THEN 'Medium ($1000-$4999)'
      WHEN ABS(ft.transaction_amount) >= 100 THEN 'Small ($100-$999)'
      ELSE 'Micro (<$100)'
    END AS transaction_size_category,
    
    -- Frequency classification (recurring vs one-off)
    CASE 
      WHEN COUNT(*) OVER (
        PARTITION BY dc.level_2_subcategory, ABS(ft.transaction_amount)::int
        ORDER BY ft.transaction_date 
        RANGE BETWEEN INTERVAL '60 days' PRECEDING AND CURRENT ROW
      ) > 2 THEN 'Recurring'
      ELSE 'One-off'
    END AS frequency_pattern,
    
    ABS(ft.transaction_amount) AS outflow_amount
    
  FROM {{ ref('fct_transactions_enhanced') }} ft
  LEFT JOIN {{ ref('dim_accounts_enhanced') }} da
    ON ft.account_key = da.account_key
  LEFT JOIN {{ ref('dim_categories_enhanced') }} dc
    ON ft.category_key = dc.category_key
  WHERE ft.transaction_amount < 0  -- Only outflows
    AND NOT COALESCE(ft.is_internal_transfer, FALSE)  -- Exclude internal transfers
    AND ft.transaction_date >= CURRENT_DATE - INTERVAL '24 months'  -- Last 2 years
),

monthly_summary AS (
  SELECT 
    year_month,
    period_date,
    
    -- Total outflows by category
    SUM(outflow_amount) AS total_outflows,
    COUNT(*) AS total_transactions,
    AVG(outflow_amount) AS avg_transaction_size,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY outflow_amount) AS median_transaction_size,
    
    -- Top expense groups
    SUM(CASE WHEN expense_group = 'Food & Dining' THEN outflow_amount ELSE 0 END) AS food_dining,
    SUM(CASE WHEN expense_group = 'Household & Utilities' THEN outflow_amount ELSE 0 END) AS household_utilities,
    SUM(CASE WHEN expense_group = 'Housing & Mortgage' THEN outflow_amount ELSE 0 END) AS housing_mortgage,
    SUM(CASE WHEN expense_group = 'Transportation' THEN outflow_amount ELSE 0 END) AS transportation,
    SUM(CASE WHEN expense_group = 'Shopping & Retail' THEN outflow_amount ELSE 0 END) AS shopping_retail,
    SUM(CASE WHEN expense_group = 'Family & Kids' THEN outflow_amount ELSE 0 END) AS family_kids,
    SUM(CASE WHEN expense_group = 'Health & Wellness' THEN outflow_amount ELSE 0 END) AS health_wellness,
    SUM(CASE WHEN expense_group = 'Entertainment' THEN outflow_amount ELSE 0 END) AS entertainment,
    SUM(CASE WHEN expense_group = 'Travel' THEN outflow_amount ELSE 0 END) AS travel,
    SUM(CASE WHEN expense_group = 'Gifts & Charity' THEN outflow_amount ELSE 0 END) AS gifts_charity,
    SUM(CASE WHEN expense_group = 'Insurance' THEN outflow_amount ELSE 0 END) AS insurance,
    SUM(CASE WHEN expense_group = 'Investments' THEN outflow_amount ELSE 0 END) AS investments,
    SUM(CASE WHEN expense_group = 'Taxes' THEN outflow_amount ELSE 0 END) AS taxes,
    SUM(CASE WHEN expense_group = 'Uncategorized' THEN outflow_amount ELSE 0 END) AS uncategorized,
    
    -- Transaction size analysis
    SUM(CASE WHEN transaction_size_category = 'Large (≥$5000)' THEN outflow_amount ELSE 0 END) AS large_transactions,
    COUNT(CASE WHEN transaction_size_category = 'Large (≥$5000)' THEN 1 END) AS large_transaction_count,
    SUM(CASE WHEN transaction_size_category = 'Medium ($1000-$4999)' THEN outflow_amount ELSE 0 END) AS medium_transactions,
    COUNT(CASE WHEN transaction_size_category = 'Medium ($1000-$4999)' THEN 1 END) AS medium_transaction_count,
    
    -- Frequency pattern analysis
    SUM(CASE WHEN frequency_pattern = 'Recurring' THEN outflow_amount ELSE 0 END) AS recurring_expenses,
    SUM(CASE WHEN frequency_pattern = 'One-off' THEN outflow_amount ELSE 0 END) AS oneoff_expenses,
    COUNT(CASE WHEN frequency_pattern = 'Recurring' THEN 1 END) AS recurring_transaction_count,
    COUNT(CASE WHEN frequency_pattern = 'One-off' THEN 1 END) AS oneoff_transaction_count,
    
    -- Account analysis
    COUNT(DISTINCT account_name) AS accounts_used,
    MAX(outflow_amount) AS largest_single_outflow
    
  FROM outflows_base
  GROUP BY year_month, period_date
),

detailed_breakdown AS (
  SELECT 
    year_month,
    period_date,
    expense_group AS category,
    SUM(outflow_amount) AS category_amount,
    COUNT(*) AS category_transaction_count,
    AVG(outflow_amount) AS avg_category_transaction_size,
    
    -- Most common subcategories within each group
    STRING_AGG(DISTINCT level_2_subcategory, ', ' ORDER BY level_2_subcategory) 
      FILTER (WHERE level_2_subcategory IS NOT NULL) AS subcategories,
    
    -- Largest transactions in category
    MAX(outflow_amount) AS largest_category_transaction,
    
    -- Account distribution
    STRING_AGG(DISTINCT account_name, ', ' ORDER BY account_name) AS accounts_used,
    
    -- Frequency analysis
    SUM(CASE WHEN frequency_pattern = 'Recurring' THEN outflow_amount ELSE 0 END) AS recurring_amount,
    SUM(CASE WHEN frequency_pattern = 'One-off' THEN outflow_amount ELSE 0 END) AS oneoff_amount
    
  FROM outflows_base
  GROUP BY year_month, period_date, expense_group
),

trends_analysis AS (
  SELECT 
    ms.*,
    
    -- Month-over-month changes
    LAG(total_outflows) OVER (ORDER BY period_date) AS prev_month_outflows,
    LAG(food_dining) OVER (ORDER BY period_date) AS prev_month_food,
    LAG(housing_mortgage) OVER (ORDER BY period_date) AS prev_month_housing,
    LAG(household_utilities) OVER (ORDER BY period_date) AS prev_month_utilities,
    
    -- Rolling 3-month averages
    AVG(total_outflows) OVER (
      ORDER BY period_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3m_avg_outflows,
    
    AVG(food_dining) OVER (
      ORDER BY period_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3m_avg_food,
    
    AVG(housing_mortgage) OVER (
      ORDER BY period_date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3m_avg_housing,
    
    -- Year-over-year comparisons
    LAG(total_outflows, 12) OVER (ORDER BY period_date) AS yoy_prev_outflows,
    LAG(food_dining, 12) OVER (ORDER BY period_date) AS yoy_prev_food,
    LAG(housing_mortgage, 12) OVER (ORDER BY period_date) AS yoy_prev_housing
    
  FROM monthly_summary ms
)

SELECT 
  ta.*,
  
  -- Calculate percentage changes
  CASE 
    WHEN prev_month_outflows > 0 
    THEN ((total_outflows - prev_month_outflows) / prev_month_outflows) * 100
    ELSE NULL 
  END AS mom_change_percent,
  
  CASE 
    WHEN yoy_prev_outflows > 0 
    THEN ((total_outflows - yoy_prev_outflows) / yoy_prev_outflows) * 100
    ELSE NULL 
  END AS yoy_change_percent,
  
  -- Category percentage of total
  CASE WHEN total_outflows > 0 THEN (food_dining / total_outflows) * 100 ELSE 0 END AS food_dining_pct,
  CASE WHEN total_outflows > 0 THEN (housing_mortgage / total_outflows) * 100 ELSE 0 END AS housing_mortgage_pct,
  CASE WHEN total_outflows > 0 THEN (household_utilities / total_outflows) * 100 ELSE 0 END AS household_utilities_pct,
  CASE WHEN total_outflows > 0 THEN (transportation / total_outflows) * 100 ELSE 0 END AS transportation_pct,
  CASE WHEN total_outflows > 0 THEN (shopping_retail / total_outflows) * 100 ELSE 0 END AS shopping_retail_pct,
  
  -- Transaction size analysis
  CASE WHEN total_outflows > 0 THEN (large_transactions / total_outflows) * 100 ELSE 0 END AS large_transactions_pct,
  CASE WHEN total_outflows > 0 THEN (recurring_expenses / total_outflows) * 100 ELSE 0 END AS recurring_expenses_pct,
  
  -- Trend indicators
  CASE 
    WHEN total_outflows > rolling_3m_avg_outflows * 1.1 THEN 'Above Average'
    WHEN total_outflows < rolling_3m_avg_outflows * 0.9 THEN 'Below Average'
    ELSE 'Normal'
  END AS spending_pattern,
  
  -- Insights
  CASE 
    WHEN large_transaction_count > 5 THEN 'High number of large transactions'
    WHEN (large_transactions / total_outflows) > 0.5 THEN 'Large transactions drive spending'
    WHEN (recurring_expenses / total_outflows) > 0.8 THEN 'Mostly recurring expenses'
    WHEN (oneoff_expenses / total_outflows) > 0.4 THEN 'Significant one-off spending'
    ELSE 'Balanced spending pattern'
  END AS spending_insight,
  
  CURRENT_TIMESTAMP AS report_generated_at
  
FROM trends_analysis ta
ORDER BY period_date DESC