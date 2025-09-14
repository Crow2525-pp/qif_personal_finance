{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['period_date'], 'unique': true},
      {'columns': ['alert_level'], 'unique': false}
    ]
  )
}}

WITH latest_period AS (
  SELECT MAX(period_date) AS current_period
  FROM {{ ref('viz_detailed_outflows_breakdown') }}
),

current_outflows AS (
  SELECT *
  FROM {{ ref('viz_detailed_outflows_breakdown') }}
  WHERE period_date = (SELECT current_period FROM latest_period)
),

previous_outflows AS (
  SELECT *
  FROM {{ ref('viz_detailed_outflows_breakdown') }}
  WHERE period_date = (SELECT current_period - INTERVAL '1 month' FROM latest_period)
),

yoy_outflows AS (
  SELECT *
  FROM {{ ref('viz_detailed_outflows_breakdown') }}
  WHERE period_date = (SELECT current_period - INTERVAL '1 year' FROM latest_period)
),

top_drivers AS (
  SELECT 
    driver_type,
    category,
    description,
    amount,
    pct_of_monthly_outflows,
    impact_level,
    recommended_action
  FROM {{ ref('viz_top_outflows_drivers') }}
  WHERE period_date = (SELECT current_period FROM latest_period)
    AND rank_in_month <= 5
  ORDER BY amount DESC
),

key_metrics AS (
  SELECT 
    co.period_date,
    co.year_month,
    co.total_outflows,
    co.total_transactions,
    co.avg_transaction_size,
    co.median_transaction_size,
    co.spending_pattern,
    co.spending_insight,
    
    -- Month-over-month comparisons
    po.total_outflows AS prev_month_outflows,
    CASE 
      WHEN po.total_outflows > 0 
      THEN ((co.total_outflows - po.total_outflows) / po.total_outflows) * 100
      ELSE NULL 
    END AS mom_outflows_change_pct,
    
    -- Year-over-year comparisons
    yo.total_outflows AS yoy_prev_outflows,
    CASE 
      WHEN yo.total_outflows > 0 
      THEN ((co.total_outflows - yo.total_outflows) / yo.total_outflows) * 100
      ELSE NULL 
    END AS yoy_outflows_change_pct,
    
    -- Category breakdown (top 5)
    co.food_dining,
    co.housing_mortgage,
    co.household_utilities,
    co.transportation,
    co.shopping_retail,
    
    -- Category percentages
    co.food_dining_pct,
    co.housing_mortgage_pct,
    co.household_utilities_pct,
    co.transportation_pct,
    co.shopping_retail_pct,
    
    -- Transaction size analysis
    co.large_transactions,
    co.large_transaction_count,
    co.large_transactions_pct,
    co.recurring_expenses_pct,
    
    -- Comparison metrics
    CASE 
      WHEN po.food_dining > 0 
      THEN ((co.food_dining - po.food_dining) / po.food_dining) * 100
      ELSE NULL 
    END AS mom_food_change_pct,
    
    CASE 
      WHEN po.housing_mortgage > 0 
      THEN ((co.housing_mortgage - po.housing_mortgage) / po.housing_mortgage) * 100
      ELSE NULL 
    END AS mom_housing_change_pct,
    
    CASE 
      WHEN po.household_utilities > 0 
      THEN ((co.household_utilities - po.household_utilities) / po.household_utilities) * 100
      ELSE NULL 
    END AS mom_utilities_change_pct
    
  FROM current_outflows co
  LEFT JOIN previous_outflows po
    ON co.year_month = po.year_month
  LEFT JOIN yoy_outflows yo
    ON co.year_month = yo.year_month
),

alert_analysis AS (
  SELECT 
    km.*,
    
    -- Alert level determination
    CASE 
      WHEN km.mom_outflows_change_pct > 20 THEN 'HIGH'
      WHEN km.mom_outflows_change_pct > 10 THEN 'MEDIUM'
      WHEN km.mom_outflows_change_pct < -20 THEN 'INFO'
      WHEN km.large_transactions_pct > 50 THEN 'MEDIUM'
      WHEN km.prev_month_outflows > 0 AND km.total_outflows > km.prev_month_outflows * 1.3 THEN 'HIGH'
      ELSE 'LOW'
    END AS alert_level,
    
    -- Key insights generation
    CASE 
      WHEN km.mom_outflows_change_pct > 20 THEN 'Significant increase in monthly outflows'
      WHEN km.large_transaction_count > 5 THEN 'High number of large transactions'
      WHEN km.food_dining_pct > 25 THEN 'Food & dining expenses are high'
      WHEN km.recurring_expenses_pct < 60 THEN 'Unusual spending pattern with many one-off expenses'
      WHEN km.yoy_outflows_change_pct > 15 THEN 'Annual spending trend increasing'
      ELSE 'Normal spending patterns'
    END AS primary_insight,
    
    -- Recommendations
    CASE 
      WHEN km.mom_outflows_change_pct > 20 THEN 'Review recent large transactions and identify drivers'
      WHEN km.large_transaction_count > 5 THEN 'Validate necessity of large purchases'
      WHEN km.food_dining_pct > 25 THEN 'Consider meal planning and dining budget'
      WHEN km.recurring_expenses_pct < 60 THEN 'Investigate one-off spending categories'
      ELSE 'Continue monitoring trends'
    END AS recommendation,
    
    -- Trend direction
    CASE 
      WHEN km.mom_outflows_change_pct > 5 THEN '↑ Increasing'
      WHEN km.mom_outflows_change_pct < -5 THEN '↓ Decreasing' 
      ELSE '→ Stable'
    END AS trend_direction,
    
    -- Volatility indicator
    ABS(km.mom_outflows_change_pct) AS outflows_volatility
    
  FROM key_metrics km
),

summary_stats AS (
  SELECT 
    aa.*,
    
    -- Budget variance (simple approximation based on previous month)
    CASE 
      WHEN aa.prev_month_outflows > 0 AND aa.total_outflows > aa.prev_month_outflows * 1.2 THEN 'Over Budget'
      WHEN aa.prev_month_outflows > 0 AND aa.total_outflows < aa.prev_month_outflows * 0.8 THEN 'Under Budget'
      ELSE 'On Track'
    END AS budget_status,
    
    -- Efficiency metrics
    aa.total_outflows / NULLIF(aa.total_transactions, 0) AS avg_outflow_per_transaction,
    
    -- Context for dashboard
    CASE 
      WHEN aa.alert_level = 'HIGH' THEN '🔴 Attention Required'
      WHEN aa.alert_level = 'MEDIUM' THEN '🟡 Monitor Closely'
      WHEN aa.alert_level = 'INFO' THEN '🔵 Notable Change'
      ELSE '🟢 Normal Operations'
    END AS dashboard_status,
    
    CURRENT_TIMESTAMP AS report_generated_at
    
  FROM alert_analysis aa
)

SELECT 
  -- Period information
  period_date,
  year_month,
  
  -- Key metrics
  total_outflows,
  total_transactions,
  avg_transaction_size,
  median_transaction_size,
  
  -- Change metrics  
  mom_outflows_change_pct,
  yoy_outflows_change_pct,
  trend_direction,
  outflows_volatility,
  
  -- Category breakdown
  food_dining,
  food_dining_pct,
  mom_food_change_pct,
  housing_mortgage,
  housing_mortgage_pct,
  mom_housing_change_pct,
  household_utilities,
  household_utilities_pct,
  mom_utilities_change_pct,
  transportation,
  transportation_pct,
  shopping_retail,
  shopping_retail_pct,
  
  -- Transaction analysis
  large_transactions,
  large_transaction_count,
  large_transactions_pct,
  recurring_expenses_pct,
  
  -- Insights and alerts
  alert_level,
  dashboard_status,
  primary_insight,
  recommendation,
  spending_pattern,
  spending_insight,
  budget_status,
  
  report_generated_at
  
FROM summary_stats
ORDER BY period_date DESC