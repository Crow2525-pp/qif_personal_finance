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

merchant_spending_current AS (
  -- Get top merchants for current month
  SELECT
    vsa.vendor_name,
    vsa.category,
    vsa.spending_tier,
    vsa.total_lifetime_spend,
    vsa.spend_last_12_months,
    vsa.spend_last_90_days,
    vsa.appears_subscription_like,
    vsa.days_since_last_transaction,
    vsa.vendor_relationship_status,
    vsa.average_transaction_amount,
    vsa.spending_consistency_score,
    vsa.avg_transactions_per_month,
    ROW_NUMBER() OVER (ORDER BY vsa.spend_last_12_months DESC) AS merchant_spend_rank
  FROM {{ ref('rpt_vendor_spending_analysis') }} vsa
  WHERE spend_last_90_days > 0
  ORDER BY vsa.spend_last_12_months DESC
  LIMIT 20
),

merchant_monthly_trends AS (
  -- Calculate merchant-level month-over-month changes
  SELECT
    ft.transaction_date,
    TO_CHAR(ft.transaction_date, 'YYYY-MM') AS merchant_period,
    TO_DATE(TO_CHAR(ft.transaction_date, 'YYYY-MM') || '-01', 'YYYY-MM-DD') AS merchant_period_date,
    COALESCE(
      NULLIF(TRIM(ft.transaction_description), ''),
      NULLIF(TRIM(ft.transaction_memo), ''),
      'Unknown Vendor'
    ) AS vendor_name,
    dc.level_1_category AS category,
    ABS(ft.transaction_amount) AS transaction_amount
  FROM {{ ref('fct_transactions') }} ft
  LEFT JOIN {{ ref('dim_categories') }} dc
    ON ft.category_key = dc.category_key
  WHERE ft.transaction_amount < 0
    AND NOT COALESCE(ft.is_internal_transfer, FALSE)
    AND NOT COALESCE(ft.is_financial_service, FALSE)
    AND ft.transaction_date >= (SELECT current_period - INTERVAL '3 months' FROM latest_period)
),

merchant_monthly_agg AS (
  SELECT
    vendor_name,
    category,
    merchant_period_date,
    SUM(transaction_amount) AS monthly_merchant_spend,
    COUNT(*) AS monthly_transaction_count,
    AVG(transaction_amount) AS monthly_avg_amount,
    STDDEV(transaction_amount) AS monthly_stddev_amount
  FROM merchant_monthly_trends
  GROUP BY vendor_name, category, merchant_period_date
),

merchant_trends_final AS (
  SELECT
    vendor_name,
    category,
    merchant_period_date,
    monthly_merchant_spend,
    monthly_transaction_count,
    monthly_avg_amount,
    monthly_stddev_amount,
    LAG(monthly_merchant_spend) OVER (PARTITION BY vendor_name ORDER BY merchant_period_date) AS prev_month_spend,
    CASE
      WHEN LAG(monthly_merchant_spend) OVER (PARTITION BY vendor_name ORDER BY merchant_period_date) > 0
      THEN ((monthly_merchant_spend - LAG(monthly_merchant_spend) OVER (PARTITION BY vendor_name ORDER BY merchant_period_date)) /
            LAG(monthly_merchant_spend) OVER (PARTITION BY vendor_name ORDER BY merchant_period_date)) * 100
      ELSE NULL
    END AS merchant_mom_change_pct,
    -- Price change detection for repeat merchants
    CASE
      WHEN monthly_avg_amount > 0 AND LAG(monthly_avg_amount) OVER (PARTITION BY vendor_name ORDER BY merchant_period_date) > 0
      THEN LAG(monthly_avg_amount) OVER (PARTITION BY vendor_name ORDER BY merchant_period_date) - monthly_avg_amount
      ELSE NULL
    END AS avg_charge_delta
  FROM merchant_monthly_agg
),

top_merchants_with_trends AS (
  SELECT
    mtf.vendor_name,
    mtf.category,
    mtf.merchant_period_date,
    mtf.monthly_merchant_spend,
    mtf.merchant_mom_change_pct,
    mtf.avg_charge_delta,
    msc.merchant_spend_rank,
    msc.spending_tier,
    msc.appears_subscription_like,
    msc.vendor_relationship_status,
    msc.spending_consistency_score
  FROM merchant_trends_final mtf
  LEFT JOIN merchant_spending_current msc
    ON mtf.vendor_name = msc.vendor_name
  WHERE mtf.merchant_period_date = (SELECT current_period FROM latest_period)
    AND msc.merchant_spend_rank <= 20
),

subscription_candidates AS (
  -- Identify subscription-like merchants and cancellation candidates
  SELECT
    vsa.vendor_name,
    vsa.category,
    vsa.appears_subscription_like,
    vsa.vendor_relationship_status,
    vsa.spending_consistency_score,
    vsa.days_since_last_transaction,
    vsa.average_transaction_amount,
    vsa.avg_transactions_per_month,
    vsa.spend_last_90_days,
    vsa.spend_last_12_months,
    CASE
      WHEN vsa.appears_subscription_like AND vsa.days_since_last_transaction <= 30 THEN 'Active Subscription'
      WHEN vsa.appears_subscription_like AND vsa.days_since_last_transaction > 30 AND vsa.days_since_last_transaction <= 90 THEN 'Dormant Subscription'
      WHEN vsa.appears_subscription_like AND vsa.days_since_last_transaction > 90 THEN 'Inactive Subscription'
      ELSE NULL
    END AS subscription_status,
    CASE
      WHEN vsa.appears_subscription_like AND vsa.days_since_last_transaction > 90
           AND vsa.spend_last_90_days = 0 THEN TRUE
      ELSE FALSE
    END AS is_cancellation_candidate
  FROM {{ ref('rpt_vendor_spending_analysis') }} vsa
  WHERE vsa.appears_subscription_like = TRUE
    OR (vsa.avg_transactions_per_month >= 0.8 AND vsa.spending_consistency_score > 0.85)
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
),

final_report AS (
  SELECT
    -- Period information
    ss.period_date,
    ss.year_month,

    -- Key metrics
    ss.total_outflows,
    ss.total_transactions,
    ss.avg_transaction_size,
    ss.median_transaction_size,

    -- Change metrics
    ss.mom_outflows_change_pct,
    ss.yoy_outflows_change_pct,
    ss.trend_direction,
    ss.outflows_volatility,

    -- Category breakdown
    ss.food_dining,
    ss.food_dining_pct,
    ss.mom_food_change_pct,
    ss.housing_mortgage,
    ss.housing_mortgage_pct,
    ss.mom_housing_change_pct,
    ss.household_utilities,
    ss.household_utilities_pct,
    ss.mom_utilities_change_pct,
    ss.transportation,
    ss.transportation_pct,
    ss.shopping_retail,
    ss.shopping_retail_pct,
    ss.uncategorized,
    ss.uncategorized_pct,
    ss.mom_uncategorized_change_pct,

    -- Transaction analysis
    ss.large_transactions,
    ss.large_transaction_count,
    ss.large_transactions_pct,
    ss.recurring_expenses_pct,

    -- Insights and alerts
    ss.alert_level,
    ss.dashboard_status,
    ss.primary_insight,
    ss.recommendation,
    ss.spending_pattern,
    ss.spending_insight,
    ss.budget_status,

    -- Merchant insights - top merchants (store as JSON array for dashboard)
    (
      SELECT json_agg(
        json_build_object(
          'rank', mwt.merchant_spend_rank,
          'merchant_name', mwt.vendor_name,
          'category', mwt.category,
          'monthly_spend', ROUND(mwt.monthly_merchant_spend::numeric, 2),
          'mom_change_pct', ROUND(mwt.merchant_mom_change_pct::numeric, 2),
          'spending_tier', mwt.spending_tier,
          'price_change_delta', ROUND(COALESCE(mwt.avg_charge_delta, 0)::numeric, 2)
        ) ORDER BY mwt.merchant_spend_rank
      )
      FROM top_merchants_with_trends mwt
    ) AS top_merchants,

    -- Subscription insights - identify recurring charges and cancellation opportunities
    (
      SELECT json_agg(
        json_build_object(
          'merchant_name', sc.vendor_name,
          'category', sc.category,
          'subscription_status', sc.subscription_status,
          'is_cancellation_candidate', sc.is_cancellation_candidate,
          'monthly_cost', ROUND(sc.average_transaction_amount::numeric, 2),
          'annual_cost', ROUND((sc.average_transaction_amount * sc.avg_transactions_per_month * 12)::numeric, 2),
          'consistency_score', ROUND((sc.spending_consistency_score * 100)::numeric, 1),
          'last_transaction_days_ago', sc.days_since_last_transaction
        ) ORDER BY sc.spend_last_12_months DESC
      )
      FROM subscription_candidates sc
      WHERE ss.period_date = (SELECT current_period FROM latest_period)
    ) AS subscription_insights,

    -- Merchant price change detection (charges with significant variance)
    (
      SELECT json_agg(
        json_build_object(
          'merchant_name', mtf.vendor_name,
          'category', mtf.category,
          'current_avg_charge', ROUND(mtf.monthly_avg_amount::numeric, 2),
          'previous_avg_charge', ROUND((mtf.monthly_avg_amount + mtf.avg_charge_delta)::numeric, 2),
          'charge_delta', ROUND(COALESCE(mtf.avg_charge_delta, 0)::numeric, 2),
          'delta_percentage', CASE
            WHEN mtf.monthly_avg_amount > 0 AND mtf.avg_charge_delta IS NOT NULL
            THEN ROUND((mtf.avg_charge_delta / mtf.monthly_avg_amount * 100)::numeric, 1)
            ELSE NULL
          END,
          'transaction_count', mtf.monthly_transaction_count
        ) ORDER BY ABS(COALESCE(mtf.avg_charge_delta, 0)) DESC
      )
      FROM merchant_trends_final mtf
      WHERE mtf.merchant_period_date = (SELECT current_period FROM latest_period)
        AND mtf.avg_charge_delta IS NOT NULL
        AND ABS(mtf.avg_charge_delta) > 5
      LIMIT 10
    ) AS price_changes_by_merchant,

    ss.report_generated_at

  FROM summary_stats ss
)

SELECT * FROM final_report
ORDER BY period_date DESC
