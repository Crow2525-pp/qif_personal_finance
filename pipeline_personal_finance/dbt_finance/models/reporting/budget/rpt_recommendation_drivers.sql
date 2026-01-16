{{
  config(
    materialized='table'
  )
}}

-- Links cash flow recommendations to specific categories and their top transactions
-- Provides actionable insights with traceable root causes

WITH latest_month_data AS (
  SELECT
    MAX(budget_year_month) AS latest_month
  FROM {{ ref('rpt_cash_flow_analysis') }}
  WHERE budget_year_month < TO_CHAR(CURRENT_DATE, 'YYYY-MM')
),

cash_flow_base AS (
  SELECT
    cf.budget_year_month,
    cf.net_cash_flow,
    cf.cash_flow_recommendation,
    cf.total_inflows,
    cf.total_outflows,
    cf.cash_flow_trend,
    cf.cash_flow_status,
    cf.rolling_3m_avg_net_flow,
    cf.outflow_to_inflow_ratio,
    cf.mom_outflow_change_percent,
    cf.cash_flow_efficiency_score
  FROM {{ ref('rpt_cash_flow_analysis') }} cf
  CROSS JOIN latest_month_data lm
  WHERE cf.budget_year_month = lm.latest_month
),

-- Get top spending categories for the month
top_outflow_categories AS (
  SELECT
    cfd.budget_year_month,
    cfd.category,
    cfd.subcategory,
    cfd.total_outflows,
    cfd.mom_variance,
    cfd.mom_pct_change,
    cfd.rolling_avg_variance,
    cfd.spending_flag,
    ROW_NUMBER() OVER (ORDER BY cfd.total_outflows DESC) as spending_rank
  FROM {{ ref('rpt_cash_flow_drivers_analysis') }} cfd
  CROSS JOIN latest_month_data lm
  WHERE cfd.budget_year_month = lm.latest_month
    AND cfd.total_outflows > 100
  LIMIT 5
),

-- Get top inflow sources
top_inflow_sources AS (
  SELECT
    t.transaction_year || '-' || LPAD(t.transaction_month::TEXT, 2, '0') as budget_year_month,
    dc.level_1_category as category,
    SUM(ABS(t.transaction_amount)) as total_inflows,
    COUNT(*) as transaction_count,
    ROW_NUMBER() OVER (ORDER BY SUM(ABS(t.transaction_amount)) DESC) as inflow_rank
  FROM {{ ref('fct_transactions') }} t
  LEFT JOIN {{ ref('dim_categories') }} dc ON t.category_key = dc.category_key
  WHERE t.is_income_transaction = true
    AND t.transaction_year || '-' || LPAD(t.transaction_month::TEXT, 2, '0') =
        (SELECT MAX(budget_year_month) FROM latest_month_data)
  GROUP BY
    t.transaction_year || '-' || LPAD(t.transaction_month::TEXT, 2, '0'),
    dc.level_1_category
  LIMIT 3
),

-- Get key drivers based on recommendation
recommendation_drivers AS (
  SELECT
    cf.budget_year_month,
    cf.cash_flow_recommendation,
    CASE
      -- Critical - focus on highest outflows
      WHEN cf.cash_flow_efficiency_score < 40 THEN
        'Focus on reducing top 3 spending categories'
      -- Negative cash flow declining
      WHEN cf.net_cash_flow < 0 AND cf.cash_flow_trend = 'Declining' THEN
        'Urgent: Spending is increasing; identify and cut high-variance categories'
      -- Very tight cash flow
      WHEN cf.outflow_to_inflow_ratio > 0.95 THEN
        'Caution: 95%+ of inflows spent; reduce discretionary spending'
      -- Excellent - opportunity
      WHEN cf.net_cash_flow > cf.rolling_3m_avg_net_flow * 1.5 THEN
        'Excellent: Consider increasing savings or investment contributions'
      -- Good - maintain
      WHEN cf.cash_flow_efficiency_score > 80 THEN
        'Good: Maintain current spending patterns and continue saving'
      -- Monitor - default
      ELSE
        'Review: Compare top categories against your budget targets'
    END as driver_focus,

    -- Most impactful category (by absolute outflow or variance)
    CASE
      WHEN cf.cash_flow_trend = 'Declining' THEN
        'High-variance spending categories'
      ELSE
        'Top spending categories'
    END as category_focus_type,

    cf.net_cash_flow,
    cf.total_inflows,
    cf.total_outflows,
    cf.mom_outflow_change_percent,
    cf.cash_flow_efficiency_score,
    CURRENT_TIMESTAMP as report_generated_at

  FROM cash_flow_base cf
),

-- Combine into final linked structure
final_drivers AS (
  SELECT
    rd.budget_year_month,
    rd.cash_flow_recommendation,
    rd.driver_focus as recommendation_driver,
    rd.category_focus_type,

    -- Top 3 outflow categories for action
    toc.category as top_category_1,
    toc.total_outflows as top_category_1_amount,
    toc.spending_flag as top_category_1_flag,

    -- Inflow context
    tis.category as primary_income_source,
    ROUND(tis.total_inflows, 2) as primary_income_amount,

    -- Trend info
    rd.net_cash_flow,
    ROUND(rd.total_inflows, 2) as total_inflows,
    ROUND(rd.total_outflows, 2) as total_outflows,
    rd.mom_outflow_change_percent,
    rd.cash_flow_efficiency_score,
    rd.report_generated_at

  FROM recommendation_drivers rd
  LEFT JOIN top_outflow_categories toc ON rd.budget_year_month = toc.budget_year_month
    AND toc.spending_rank = 1
  LEFT JOIN top_inflow_sources tis ON rd.budget_year_month = tis.budget_year_month
    AND tis.inflow_rank = 1
)

SELECT * FROM final_drivers
