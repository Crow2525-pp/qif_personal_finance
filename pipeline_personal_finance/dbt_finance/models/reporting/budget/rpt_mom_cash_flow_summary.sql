{{
  config(
    materialized='table'
  )
}}

-- Month-over-month cash flow summary highlighting what changed
-- Provides variance-driver links for navigation to detailed analysis

WITH cash_flow_months AS (
  SELECT
    budget_year_month,
    transaction_year,
    transaction_month,
    net_cash_flow,
    total_inflows,
    total_outflows,
    cash_flow_status,
    cash_flow_trend,
    rolling_3m_avg_net_flow,
    LAG(budget_year_month) OVER (ORDER BY transaction_year, transaction_month) as prior_month,
    LAG(net_cash_flow) OVER (ORDER BY transaction_year, transaction_month) as prior_month_net,
    LAG(total_inflows) OVER (ORDER BY transaction_year, transaction_month) as prior_month_inflows,
    LAG(total_outflows) OVER (ORDER BY transaction_year, transaction_month) as prior_month_outflows,
    LAG(cash_flow_status) OVER (ORDER BY transaction_year, transaction_month) as prior_month_status,
    LAG(cash_flow_trend) OVER (ORDER BY transaction_year, transaction_month) as prior_month_trend,
    mom_inflow_change_percent,
    mom_outflow_change_percent
  FROM {{ ref('rpt_cash_flow_analysis') }}
  WHERE budget_year_month < TO_CHAR(CURRENT_DATE, 'YYYY-MM')
  ORDER BY transaction_year DESC, transaction_month DESC
  LIMIT 2  -- Get latest two months
),

latest_two_months AS (
  SELECT
    *,
    ROW_NUMBER() OVER (ORDER BY transaction_year DESC, transaction_month DESC) as month_rank
  FROM cash_flow_months
),

latest_vs_prior AS (
  SELECT
    CASE WHEN month_rank = 1 THEN budget_year_month END as latest_month,
    CASE WHEN month_rank = 1 THEN prior_month END as prior_month,
    CASE WHEN month_rank = 1 THEN net_cash_flow END as latest_net_flow,
    CASE WHEN month_rank = 1 THEN prior_month_net END as prior_month_net_flow,
    CASE WHEN month_rank = 1 THEN total_inflows END as latest_inflows,
    CASE WHEN month_rank = 1 THEN prior_month_inflows END as prior_inflows,
    CASE WHEN month_rank = 1 THEN total_outflows END as latest_outflows,
    CASE WHEN month_rank = 1 THEN prior_month_outflows END as prior_outflows,
    CASE WHEN month_rank = 1 THEN cash_flow_status END as latest_status,
    CASE WHEN month_rank = 1 THEN prior_month_status END as prior_status,
    CASE WHEN month_rank = 1 THEN cash_flow_trend END as latest_trend,
    CASE WHEN month_rank = 1 THEN prior_month_trend END as prior_trend,
    CASE WHEN month_rank = 1 THEN mom_inflow_change_percent END as inflow_change_pct,
    CASE WHEN month_rank = 1 THEN mom_outflow_change_percent END as outflow_change_pct
  FROM latest_two_months
),

change_summary AS (
  SELECT
    MAX(latest_month) as latest_month,
    MAX(prior_month) as prior_month,
    MAX(latest_net_flow) as latest_net_flow,
    MAX(prior_month_net_flow) as prior_month_net_flow,
    MAX(latest_net_flow) - MAX(prior_month_net_flow) as net_flow_change,
    CASE
      WHEN MAX(prior_month_net_flow) <> 0 THEN
        ROUND(((MAX(latest_net_flow) - MAX(prior_month_net_flow)) / ABS(MAX(prior_month_net_flow))) * 100, 1)
      ELSE NULL
    END as net_flow_change_pct,
    MAX(latest_inflows) as latest_inflows,
    MAX(prior_inflows) as prior_inflows,
    MAX(latest_inflows) - MAX(prior_inflows) as inflow_change,
    ROUND(COALESCE(MAX(inflow_change_pct), 0), 1) as inflow_change_pct,
    MAX(latest_outflows) as latest_outflows,
    MAX(prior_outflows) as prior_outflows,
    MAX(latest_outflows) - MAX(prior_outflows) as outflow_change,
    ROUND(COALESCE(MAX(outflow_change_pct), 0), 1) as outflow_change_pct,
    MAX(latest_status) as latest_status,
    MAX(prior_status) as prior_status,
    MAX(latest_trend) as latest_trend,
    MAX(prior_trend) as prior_trend
  FROM latest_vs_prior
),

final_summary AS (
  SELECT
    cs.latest_month,
    cs.prior_month,

    -- Net flow summary
    ROUND(cs.latest_net_flow, 2) as latest_month_net_flow,
    ROUND(cs.prior_month_net_flow, 2) as prior_month_net_flow,
    ROUND(cs.net_flow_change, 2) as net_flow_change_dollars,
    cs.net_flow_change_pct as net_flow_change_pct,

    -- Inflow summary
    ROUND(cs.latest_inflows, 2) as latest_month_inflows,
    ROUND(cs.prior_inflows, 2) as prior_month_inflows,
    ROUND(cs.inflow_change, 2) as inflow_change_dollars,
    cs.inflow_change_pct,

    -- Outflow summary
    ROUND(cs.latest_outflows, 2) as latest_month_outflows,
    ROUND(cs.prior_outflows, 2) as prior_month_outflows,
    ROUND(cs.outflow_change, 2) as outflow_change_dollars,
    cs.outflow_change_pct,

    -- Status changes
    cs.latest_status,
    cs.prior_status,
    CASE
      WHEN cs.latest_status = cs.prior_status THEN 'Stable'
      WHEN cs.latest_status = 'Positive' AND cs.prior_status != 'Positive' THEN 'Improved'
      WHEN cs.latest_status = 'Negative' AND cs.prior_status != 'Negative' THEN 'Declined'
      ELSE 'Changed'
    END as status_change,

    -- Trend changes
    cs.latest_trend,
    cs.prior_trend,
    CASE
      WHEN cs.latest_trend = 'Improving' THEN 'Positive - spending is declining'
      WHEN cs.latest_trend = 'Declining' THEN 'Negative - spending is increasing'
      WHEN cs.latest_trend = 'Stable' THEN 'Stable - consistent spending'
      ELSE 'Unclear'
    END as trend_description,

    -- Summary narrative
    CASE
      WHEN cs.net_flow_change > 0 AND ABS(cs.net_flow_change) > 1000 THEN
        'Excellent: Net cash flow improved by $' || ROUND(ABS(cs.net_flow_change), 0) || ' (due to ' ||
        CASE WHEN cs.outflow_change < 0 THEN 'reduced spending' ELSE 'increased income' END || ')'
      WHEN cs.net_flow_change < 0 AND ABS(cs.net_flow_change) > 1000 THEN
        'Caution: Net cash flow declined by $' || ROUND(ABS(cs.net_flow_change), 0) || ' (due to ' ||
        CASE WHEN cs.outflow_change > 0 THEN 'increased spending' ELSE 'reduced income' END || ')'
      WHEN cs.outflow_change > cs.prior_outflows * 0.10 THEN
        'Alert: Spending increased ' || ROUND(cs.outflow_change_pct, 0) || '% - review variance drivers'
      WHEN cs.inflow_change < cs.prior_inflows * -0.05 THEN
        'Alert: Income decreased ' || ROUND(ABS(cs.inflow_change_pct), 0) || '%'
      ELSE
        'Neutral: Cash flow metrics stable month-over-month'
    END as change_summary,

    -- Link to variance drivers dashboard
    CASE
      WHEN cs.outflow_change > cs.prior_outflows * 0.10 THEN
        'Review: Month-over-Month Variance Analysis panel'
      WHEN ABS(cs.net_flow_change) > 1000 THEN
        'Review: Cash Flow by Category and Month-over-Month Variance Analysis'
      ELSE
        'Review: Cash Flow Metrics and Trends'
    END as recommended_action_link,

    CURRENT_TIMESTAMP as report_generated_at

  FROM change_summary cs
)

SELECT * FROM final_summary
