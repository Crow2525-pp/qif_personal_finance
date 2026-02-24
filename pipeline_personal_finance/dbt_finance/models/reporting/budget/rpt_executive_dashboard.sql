{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['dashboard_month'], 'unique': true}
    ]
  )
}}
{#
Dashboard contract for this model (coordinate SQL + dashboard JSON changes together):
- executive_dashboard:
  - panel 132 (Data Freshness): dashboard_generated_at
  - panel 198 (Priority Recommendation): priority_recommendation, accounts_with_issues
  - panel 1994 (Financial Health Rating): overall_financial_health_rating, current_savings_tier
- expense_performance:
  - ratio/score panels: dashboard_year, dashboard_month_num, monthly_savings_rate_percent_pct, expense_to_income_ratio_pct, cash_flow_score
- exec-mobile-overview:
  - panel 1 (Health Scores): expense_to_income_ratio_pct, overall_financial_health_score, savings_health_score, cash_flow_score
  - panel 2 (Monthly Snapshot): monthly_income, monthly_expenses, monthly_net_cash_flow, monthly_savings_rate_percent
- all executive consumers: dashboard_month for latest-period row selection
#}

WITH latest_period AS (
  SELECT MAX(budget_year_month) AS latest_month
  FROM {{ ref('rpt_monthly_budget_summary') }}
  WHERE budget_year_month < TO_CHAR(CURRENT_DATE, 'YYYY-MM')
),

current_month_summary AS (
  SELECT
    ms.budget_year_month,
    ms.budget_year,
    ms.budget_month,
    ms.total_income,
    ms.total_expenses,
    ms.net_cash_flow,
    ms.savings_rate_percent,
    ms.expense_ratio_percent,
    ms.rolling_3m_avg_income,
    ms.rolling_3m_avg_expenses,
    ms.ytd_income,
    ms.ytd_expenses,
    ms.ytd_net_cash_flow
  FROM {{ ref('rpt_monthly_budget_summary') }} ms
  CROSS JOIN latest_period lp
  WHERE ms.budget_year_month = lp.latest_month
),

current_net_worth AS (
  SELECT 
    net_worth,
    total_assets,
    total_liabilities,
    liquid_assets,
    mortgage_debt,
    mom_net_worth_change,
    mom_net_worth_change_percent,
    net_worth_health_score,
    debt_to_asset_ratio,
    financial_advice AS net_worth_advice,
    wealth_milestone
  FROM {{ ref('rpt_household_net_worth') }} nw
  CROSS JOIN latest_period lp
  WHERE nw.budget_year_month = lp.latest_month
),

current_savings AS (
  SELECT 
    total_savings,
    total_savings_rate_percent,
    traditional_savings_rate_percent,
    liquid_savings_rate_percent,
    investment_rate_percent,
    savings_performance_tier,
    savings_trend,
    savings_health_score,
    savings_recommendation,
    rolling_3m_avg_savings_rate,
    ytd_total_savings
  FROM {{ ref('rpt_savings_analysis') }} sa
  CROSS JOIN latest_period lp
  WHERE sa.budget_year_month = lp.latest_month
),

current_cash_flow AS (
  SELECT 
    total_inflows,
    total_outflows,
    net_cash_flow AS cf_net_cash_flow,
    cash_flow_status,
    cash_flow_trend,
    cash_flow_efficiency_score,
    cash_flow_status_rank,
    cash_flow_efficiency_percentile,
    cash_flow_status_compound,
    outflow_to_inflow_ratio,
    cash_flow_recommendation,
    operating_cash_flow,
    forecasted_next_month_net_flow
  FROM {{ ref('rpt_cash_flow_analysis') }} cf
  CROSS JOIN latest_period lp
  WHERE cf.budget_year_month = lp.latest_month
),

top_spending_categories AS (
  SELECT 
    level_1_category,
    monthly_spending,
    percent_of_total_monthly_spending,
    spending_trend_category,
    RANK() OVER (ORDER BY monthly_spending DESC) as spending_rank
  FROM {{ ref('rpt_category_spending_trends') }} ct
  CROSS JOIN latest_period lp
  WHERE ct.budget_year_month = lp.latest_month
    AND monthly_spending > 0
  ORDER BY monthly_spending DESC
  LIMIT 5
),

account_alerts AS (
  SELECT 
    COUNT(*) AS accounts_needing_attention,
    STRING_AGG(account_name, ', ' ORDER BY account_name) AS accounts_with_issues
  FROM {{ ref('rpt_account_performance') }} ap
  CROSS JOIN latest_period lp
  WHERE ap.budget_year_month = lp.latest_month
    AND ap.needs_attention_flag = TRUE
    AND COALESCE(ap.is_mortgage, FALSE) = FALSE
),

executive_summary AS (
  SELECT 
    cms.budget_year_month AS dashboard_month,
    cms.budget_year AS dashboard_year,
    cms.budget_month AS dashboard_month_num,
    
    -- FINANCIAL HEALTH OVERVIEW
    ROUND(cms.total_income, 0) AS monthly_income,
    ROUND(cms.total_expenses, 0) AS monthly_expenses,
    ROUND(cms.net_cash_flow, 0) AS monthly_net_cash_flow,
    ROUND(cms.savings_rate_percent, 3) AS monthly_savings_rate_percent,
    ROUND((cms.savings_rate_percent * 100)::numeric, 1) AS monthly_savings_rate_percent_pct,
    
    -- NET WORTH SNAPSHOT
    ROUND(cnw.net_worth, 0) AS current_net_worth,
    ROUND(cnw.total_assets, 0) AS total_assets,
    ROUND(cnw.total_liabilities, 0) AS total_liabilities,
    ROUND(cnw.liquid_assets, 0) AS liquid_assets,
    ROUND(cnw.mom_net_worth_change, 0) AS monthly_net_worth_change,
    ROUND(cnw.debt_to_asset_ratio, 1) AS debt_to_asset_ratio_percent,
    cnw.net_worth_health_score,
    
    -- SAVINGS PERFORMANCE
    ROUND(cms.net_cash_flow, 0) AS monthly_total_savings,
    ROUND(cs.total_savings_rate_percent, 3) AS comprehensive_savings_rate, -- ratio 0-1 (includes investments)
    ROUND(cs.traditional_savings_rate_percent, 3) AS traditional_savings_rate, -- ratio 0-1
    -- percent-scaled versions (0-100) for Grafana display
    ROUND((cs.total_savings_rate_percent * 100)::numeric, 1) AS comprehensive_savings_rate_pct,
    ROUND((cs.traditional_savings_rate_percent * 100)::numeric, 1) AS traditional_savings_rate_pct,
    ROUND(cs.ytd_total_savings, 0) AS ytd_total_savings,
    cs.savings_performance_tier,
    cs.savings_health_score,

    -- Use actual monthly cash flow savings rate for executive dashboard display
    ROUND(cms.savings_rate_percent, 3) AS monthly_cash_flow_savings_rate, -- ratio 0-1 (actual cash flow)
    ROUND((cms.savings_rate_percent * 100)::numeric, 1) AS monthly_cash_flow_savings_rate_pct,
    
    -- CASH FLOW HEALTH
    ccf.cash_flow_status,
    ccf.cash_flow_trend,
    ccf.cash_flow_status_rank,
    ccf.cash_flow_efficiency_percentile,
    ccf.cash_flow_status_compound,
    ROUND(ccf.cash_flow_efficiency_score, 0) AS cash_flow_score,
    ROUND(cms.expense_ratio_percent, 3) AS expense_to_income_ratio,
    ROUND((cms.expense_ratio_percent * 100)::numeric, 1) AS expense_to_income_ratio_pct,
    ROUND((ccf.cash_flow_efficiency_percentile * 100)::numeric, 1) AS cash_flow_efficiency_percentile_pct,
    
    -- PERFORMANCE SCORES (Weighted Average)
    ROUND((cnw.net_worth_health_score * 0.3 + 
           cs.savings_health_score * 0.3 + 
           ccf.cash_flow_efficiency_score * 0.4), 0) AS overall_financial_health_score,
    
    -- TRENDS (3-Month Rolling Averages)
    ROUND(cms.rolling_3m_avg_income, 0) AS three_month_avg_income,
    ROUND(cms.rolling_3m_avg_expenses, 0) AS three_month_avg_expenses,
    ROUND(cs.rolling_3m_avg_savings_rate, 3) AS three_month_avg_savings_rate, -- ratio 0-1
    ROUND(cs.rolling_3m_avg_savings_rate * 100, 1) AS three_month_avg_savings_rate_pct,
    
    -- YEAR-TO-DATE PROGRESS
    ROUND(cms.ytd_income, 0) AS ytd_income,
    ROUND(cms.ytd_expenses, 0) AS ytd_expenses,
    ROUND(cms.ytd_net_cash_flow, 0) AS ytd_net_cash_flow,
    CASE WHEN cms.ytd_income > 0 THEN ROUND((cms.ytd_net_cash_flow / cms.ytd_income), 3) ELSE 0 END AS ytd_savings_rate,
    CASE WHEN cms.ytd_income > 0 THEN ROUND(((cms.ytd_net_cash_flow / cms.ytd_income) * 100)::numeric, 1) ELSE 0 END AS ytd_savings_rate_pct,
    
    -- KEY ALERTS AND RECOMMENDATIONS
    COALESCE(aa.accounts_needing_attention, 0) AS accounts_needing_attention,
    COALESCE(aa.accounts_with_issues, '') AS accounts_with_issues,
    
    -- TOP PRIORITIES (Most Important Recommendations)
    CASE 
      WHEN cs.savings_health_score < 40 THEN cs.savings_recommendation
      WHEN cnw.net_worth_health_score < 40 THEN cnw.net_worth_advice  
      WHEN ccf.cash_flow_efficiency_score < 40 THEN ccf.cash_flow_recommendation
      WHEN aa.accounts_needing_attention > 0 AND COALESCE(aa.accounts_with_issues, '') <> '' THEN 'Review accounts flagged for attention: ' || aa.accounts_with_issues
      ELSE 'Continue current financial strategy - performance is good'
    END AS priority_recommendation,
    
    -- FINANCIAL MILESTONES STATUS
    cnw.wealth_milestone AS current_wealth_milestone,
    cs.savings_performance_tier AS current_savings_tier,
    
    -- FORECASTING
    ROUND(ccf.forecasted_next_month_net_flow, 0) AS forecasted_next_month_cash_flow,
    
    -- BENCHMARKING (use actual monthly cash flow savings rate for executive view)
    CASE
      WHEN cms.savings_rate_percent >= 0.30 THEN 'Exceptional Performance'
      WHEN cms.savings_rate_percent >= 0.20 THEN 'Above Average'
      WHEN cms.savings_rate_percent >= 0.15 THEN 'Average Performance'
      WHEN cms.savings_rate_percent >= 0.10 THEN 'Needs Improvement'
      ELSE 'Critical Improvement Needed'
    END AS savings_rate_benchmark,
    
    CASE 
      WHEN cnw.net_worth > 500000 THEN 'High Net Worth'
      WHEN cnw.net_worth > 100000 THEN 'Building Wealth'
      WHEN cnw.net_worth > 0 THEN 'Positive Net Worth'
      ELSE 'Rebuilding Phase'
    END AS net_worth_benchmark,

    -- Net Worth Benchmark rank for bar gauge (1 worst .. 5 best)
    CASE 
      WHEN cnw.net_worth < 0 AND cnw.debt_to_asset_ratio > 0.80 THEN 1 -- Below Target
      WHEN cnw.net_worth <= 0 THEN 2                                   -- Rebuilding
      WHEN cnw.net_worth > 0 AND cnw.net_worth <= 100000 THEN 3        -- On Track
      WHEN cnw.net_worth > 100000 AND cnw.net_worth <= 500000 THEN 4   -- Good
      WHEN cnw.net_worth > 500000 THEN 5                                -- Excellent
      ELSE 3
    END AS net_worth_benchmark_rank,
    
    CURRENT_TIMESTAMP AS dashboard_generated_at
    
  FROM current_month_summary cms
  LEFT JOIN current_net_worth cnw ON 1=1
  LEFT JOIN current_savings cs ON 1=1
  LEFT JOIN current_cash_flow ccf ON 1=1
  LEFT JOIN account_alerts aa ON 1=1
),

-- Add top spending categories as JSON for dashboard flexibility
top_categories_json AS (
  SELECT 
    {% if target.type == 'duckdb' %}
    to_json(
      list(
        json_object(
          'category', level_1_category,
          'amount', monthly_spending,
          'percent', percent_of_total_monthly_spending,
          'trend', spending_trend_category
        )
      )
    ) AS top_spending_categories_json
    {% else %}
    JSON_AGG(
      JSON_BUILD_OBJECT(
        'category', level_1_category,
        'amount', monthly_spending,
        'percent', percent_of_total_monthly_spending,
        'trend', spending_trend_category
      ) ORDER BY spending_rank
    ) AS top_spending_categories_json
    {% endif %}
  FROM top_spending_categories
),

final_dashboard AS (
  SELECT 
    es.*,
    tcj.top_spending_categories_json,
    
    -- Overall financial health assessment
    CASE 
      WHEN overall_financial_health_score >= 80 THEN 'Excellent'
      WHEN overall_financial_health_score >= 70 THEN 'Good'
      WHEN overall_financial_health_score >= 60 THEN 'Fair'
      WHEN overall_financial_health_score >= 50 THEN 'Needs Improvement'
      ELSE 'Critical Attention Required'
    END AS overall_financial_health_rating,
    
    -- Monthly performance vs. goals (use actual cash flow savings rate)
    CASE
      WHEN monthly_cash_flow_savings_rate >= 0.15 AND cash_flow_score >= 70 AND monthly_net_worth_change > 0
      THEN 'Exceeding Financial Goals'
      WHEN monthly_cash_flow_savings_rate >= 0.10 AND cash_flow_score >= 60 AND monthly_net_worth_change >= 0
      THEN 'Meeting Financial Goals'
      WHEN monthly_cash_flow_savings_rate >= 0.05 AND cash_flow_score >= 50
      THEN 'Progressing Toward Goals'
      ELSE 'Below Financial Goals'
    END AS monthly_goal_achievement,
    
    -- Key action items (top 3)
    CASE 
      WHEN overall_financial_health_score < 50 THEN 
        ARRAY[priority_recommendation, 'Review budget and reduce expenses', 'Consider financial planning consultation']
      WHEN accounts_needing_attention > 0 AND COALESCE(accounts_with_issues, '') <> '' THEN
        ARRAY[priority_recommendation, 'Review account performance', 'Optimize account allocation']
      WHEN monthly_cash_flow_savings_rate < 0.15 THEN
        ARRAY['Increase savings rate to 15%', priority_recommendation, 'Automate savings transfers']
      ELSE 
        ARRAY[priority_recommendation, 'Review investment allocation', 'Consider tax optimization']
    END AS top_action_items
    
  FROM executive_summary es
  LEFT JOIN top_categories_json tcj ON 1=1
)

SELECT * FROM final_dashboard
