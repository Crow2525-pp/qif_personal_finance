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

six_month_periods AS (
  SELECT DISTINCT period_date
  FROM {{ ref('viz_detailed_outflows_breakdown') }}
  WHERE period_date >= (SELECT current_period - INTERVAL '5 months' FROM latest_period)
  ORDER BY period_date DESC
),

all_outflows AS (
  SELECT *
  FROM {{ ref('viz_detailed_outflows_breakdown') }}
  WHERE period_date IN (SELECT period_date FROM six_month_periods)
),

current_outflows AS (
  SELECT *
  FROM all_outflows
  WHERE period_date = (SELECT current_period FROM latest_period)
),

previous_outflows AS (
  SELECT *
  FROM all_outflows
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

uncategorized_analysis AS (
  SELECT
    ao.period_date,
    ao.uncategorized,
    CASE WHEN ao.total_outflows > 0 THEN (ao.uncategorized / ao.total_outflows) * 100 ELSE 0 END AS uncategorized_pct,

    -- Previous month uncategorized for comparison
    LAG(ao.uncategorized) OVER (ORDER BY ao.period_date) AS prev_month_uncategorized,
    CASE
      WHEN LAG(ao.uncategorized) OVER (ORDER BY ao.period_date) > 0
      THEN ((ao.uncategorized - LAG(ao.uncategorized) OVER (ORDER BY ao.period_date)) / LAG(ao.uncategorized) OVER (ORDER BY ao.period_date)) * 100
      ELSE NULL
    END AS mom_uncategorized_change_pct,

    -- Uncategorized vs other major categories
    ao.food_dining,
    ao.housing_mortgage,
    ao.household_utilities,
    ao.transportation,
    ao.shopping_retail

  FROM all_outflows ao
),

high_value_uncategorized AS (
  SELECT
    hvu.period_start,
    hvu.total_amount_abs,
    hvu.txn_count,
    hvu.sample_memo,
    hvu.suggested_category,
    hvu.suggested_subcategory,
    hvu.confidence
  FROM {{ ref('viz_high_value_uncategorized_by_period') }} hvu
  WHERE hvu.period_type = 'month'
    AND hvu.period_start IN (SELECT period_date FROM six_month_periods)
),

key_metrics AS (
  SELECT
    ao.period_date,
    ao.year_month,
    ao.total_outflows,
    ao.total_transactions,
    ao.avg_transaction_size,
    ao.median_transaction_size,
    ao.spending_pattern,
    ao.spending_insight,

    -- Month-over-month comparisons (using LAG for each period)
    LAG(ao.total_outflows) OVER (ORDER BY ao.period_date) AS prev_month_outflows,
    CASE
      WHEN LAG(ao.total_outflows) OVER (ORDER BY ao.period_date) > 0
      THEN ((ao.total_outflows - LAG(ao.total_outflows) OVER (ORDER BY ao.period_date)) / LAG(ao.total_outflows) OVER (ORDER BY ao.period_date)) * 100
      ELSE NULL
    END AS mom_outflows_change_pct,

    -- Year-over-year comparisons (find YoY for each period if available)
    yo.total_outflows AS yoy_prev_outflows,
    CASE
      WHEN yo.total_outflows > 0
      THEN ((ao.total_outflows - yo.total_outflows) / yo.total_outflows) * 100
      ELSE NULL
    END AS yoy_outflows_change_pct,

    -- Category breakdown (top 5 + uncategorized)
    ao.food_dining,
    ao.housing_mortgage,
    ao.household_utilities,
    ao.transportation,
    ao.shopping_retail,
    ao.uncategorized,

    -- Category percentages
    ao.food_dining_pct,
    ao.housing_mortgage_pct,
    ao.household_utilities_pct,
    ao.transportation_pct,
    ao.shopping_retail_pct,
    CASE WHEN ao.total_outflows > 0 THEN (ao.uncategorized / ao.total_outflows) * 100 ELSE 0 END AS uncategorized_pct,

    -- Transaction size analysis
    ao.large_transactions,
    ao.large_transaction_count,
    ao.large_transactions_pct,
    ao.recurring_expenses_pct,

    -- Category comparison metrics (using LAG for each period)
    CASE
      WHEN LAG(ao.food_dining) OVER (ORDER BY ao.period_date) > 0
      THEN ((ao.food_dining - LAG(ao.food_dining) OVER (ORDER BY ao.period_date)) / LAG(ao.food_dining) OVER (ORDER BY ao.period_date)) * 100
      ELSE NULL
    END AS mom_food_change_pct,

    CASE
      WHEN LAG(ao.housing_mortgage) OVER (ORDER BY ao.period_date) > 0
      THEN ((ao.housing_mortgage - LAG(ao.housing_mortgage) OVER (ORDER BY ao.period_date)) / LAG(ao.housing_mortgage) OVER (ORDER BY ao.period_date)) * 100
      ELSE NULL
    END AS mom_housing_change_pct,

    CASE
      WHEN LAG(ao.household_utilities) OVER (ORDER BY ao.period_date) > 0
      THEN ((ao.household_utilities - LAG(ao.household_utilities) OVER (ORDER BY ao.period_date)) / LAG(ao.household_utilities) OVER (ORDER BY ao.period_date)) * 100
      ELSE NULL
    END AS mom_utilities_change_pct,

    -- Uncategorized comparison metrics
    CASE
      WHEN LAG(ao.uncategorized) OVER (ORDER BY ao.period_date) > 0
      THEN ((ao.uncategorized - LAG(ao.uncategorized) OVER (ORDER BY ao.period_date)) / LAG(ao.uncategorized) OVER (ORDER BY ao.period_date)) * 100
      ELSE NULL
    END AS mom_uncategorized_change_pct

  FROM all_outflows ao
  LEFT JOIN {{ ref('viz_detailed_outflows_breakdown') }} yo
    ON ao.period_date = yo.period_date + INTERVAL '1 year'
),

alert_analysis AS (
  SELECT 
    km.*,
    
    -- Alert level determination
    CASE
      WHEN km.uncategorized_pct > 30 THEN 'HIGH'
      WHEN km.mom_outflows_change_pct > 20 THEN 'HIGH'
      WHEN km.uncategorized_pct > 20 THEN 'MEDIUM'
      WHEN km.mom_outflows_change_pct > 10 THEN 'MEDIUM'
      WHEN km.mom_outflows_change_pct < -20 THEN 'INFO'
      WHEN km.large_transactions_pct > 50 THEN 'MEDIUM'
      WHEN km.prev_month_outflows > 0 AND km.total_outflows > km.prev_month_outflows * 1.3 THEN 'HIGH'
      ELSE 'LOW'
    END AS alert_level,
    
    -- Key insights generation
    CASE
      WHEN km.uncategorized_pct > 30 THEN 'High percentage of uncategorized transactions'
      WHEN km.uncategorized_pct > 20 THEN 'Significant uncategorized spending needs review'
      WHEN km.mom_outflows_change_pct > 20 THEN 'Significant increase in monthly outflows'
      WHEN km.large_transaction_count > 5 THEN 'High number of large transactions'
      WHEN km.food_dining_pct > 25 THEN 'Food & dining expenses are high'
      WHEN km.recurring_expenses_pct < 60 THEN 'Unusual spending pattern with many one-off expenses'
      WHEN km.yoy_outflows_change_pct > 15 THEN 'Annual spending trend increasing'
      ELSE 'Normal spending patterns'
    END AS primary_insight,
    
    -- Recommendations
    CASE
      WHEN km.uncategorized_pct > 30 THEN 'Urgent: Categorize transactions to identify spending patterns'
      WHEN km.uncategorized_pct > 20 THEN 'Review and categorize uncategorized transactions'
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
  uncategorized,
  uncategorized_pct,
  mom_uncategorized_change_pct,
  
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