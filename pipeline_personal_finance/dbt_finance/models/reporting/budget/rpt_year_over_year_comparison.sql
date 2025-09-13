{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['comparison_year'], 'unique': true}
    ]
  )
}}

WITH annual_summary AS (
  SELECT 
    budget_year AS comparison_year,
    
    -- Income and expense totals
    SUM(total_income) AS annual_income,
    SUM(total_expenses) AS annual_expenses,
    SUM(net_cash_flow) AS annual_net_cash_flow,
    
    -- Monthly averages
    AVG(total_income) AS avg_monthly_income,
    AVG(total_expenses) AS avg_monthly_expenses,
    AVG(net_cash_flow) AS avg_monthly_net_cash_flow,
    AVG(savings_rate_percent) AS avg_savings_rate_percent,
    
    -- Expense category totals
    SUM(mortgage_expenses) AS annual_mortgage_expenses,
    SUM(household_expenses) AS annual_household_expenses,
    SUM(food_expenses) AS annual_food_expenses,
    SUM(family_expenses) AS annual_family_expenses,
    
    -- Count metrics
    COUNT(*) AS months_with_data,
    SUM(total_transactions) AS annual_transaction_count,
    MAX(ytd_net_cash_flow) AS end_of_year_cumulative_cash_flow,
    
    -- Best and worst months
    MAX(net_cash_flow) AS best_month_net_cash_flow,
    MIN(net_cash_flow) AS worst_month_net_cash_flow,
    MAX(savings_rate_percent) AS best_month_savings_rate,
    MIN(savings_rate_percent) AS worst_month_savings_rate
    
  FROM {{ ref('rpt_monthly_budget_summary') }}
  GROUP BY budget_year
),

net_worth_annual AS (
  SELECT 
    transaction_year AS comparison_year,
    
    -- Year-end net worth positions
    MAX(CASE WHEN transaction_month = 12 THEN net_worth END) AS year_end_net_worth,
    MIN(CASE WHEN transaction_month = 1 THEN net_worth END) AS year_start_net_worth,
    
    -- Annual changes
    MAX(net_worth) - MIN(net_worth) AS annual_net_worth_change,
    AVG(net_worth) AS avg_annual_net_worth,
    
    -- Asset and liability totals (year-end)
    MAX(CASE WHEN transaction_month = 12 THEN total_assets END) AS year_end_total_assets,
    MAX(CASE WHEN transaction_month = 12 THEN total_liabilities END) AS year_end_total_liabilities,
    
    -- Debt metrics
    MIN(CASE WHEN transaction_month = 1 THEN mortgage_debt END) AS year_start_mortgage_debt,
    MAX(CASE WHEN transaction_month = 12 THEN mortgage_debt END) AS year_end_mortgage_debt,
    
    -- Best metrics
    MAX(net_worth) AS peak_annual_net_worth,
    MIN(net_worth) AS lowest_annual_net_worth,
    MAX(net_worth_health_score) AS best_net_worth_health_score
    
  FROM {{ ref('rpt_household_net_worth') }}
  GROUP BY transaction_year
),

savings_annual AS (
  SELECT 
    transaction_year AS comparison_year,
    
    -- Savings totals
    SUM(total_savings) AS annual_total_savings,
    AVG(total_savings_rate_percent) AS avg_annual_savings_rate,
    SUM(offset_savings + cash_savings) AS annual_liquid_savings,
    SUM(investment_contributions) AS annual_investment_contributions,
    
    -- Savings performance
    MAX(total_savings_rate_percent) AS best_month_savings_rate_pct,
    MIN(total_savings_rate_percent) AS worst_month_savings_rate_pct,
    MAX(total_savings) AS best_month_savings_amount,
    
    -- Year-end savings metrics
    MAX(CASE WHEN transaction_month = 12 THEN ytd_savings_rate_percent END) AS year_end_ytd_savings_rate,
    MAX(CASE WHEN transaction_month = 12 THEN savings_health_score END) AS year_end_savings_health_score
    
  FROM {{ ref('rpt_savings_analysis') }}
  GROUP BY transaction_year
),

cash_flow_annual AS (
  SELECT 
    transaction_year AS comparison_year,
    
    -- Cash flow totals
    SUM(total_inflows) AS annual_total_inflows,
    SUM(total_outflows) AS annual_total_outflows,
    SUM(net_cash_flow) AS annual_net_cash_flow_alt,
    
    -- Average ratios
    AVG(cash_flow_efficiency_score) AS avg_cash_flow_efficiency,
    AVG(outflow_to_inflow_ratio) AS avg_outflow_to_inflow_ratio,
    
    -- Cash flow consistency
    COUNT(CASE WHEN cash_flow_status = 'Positive' THEN 1 END) AS months_positive_cash_flow,
    COUNT(CASE WHEN cash_flow_status = 'Negative' THEN 1 END) AS months_negative_cash_flow
    
  FROM {{ ref('rpt_cash_flow_analysis') }}
  GROUP BY transaction_year
),

combined_annual_metrics AS (
  SELECT 
    a.comparison_year,
    
    -- Income and expense metrics
    a.annual_income,
    a.annual_expenses,
    a.annual_net_cash_flow,
    a.avg_monthly_income,
    a.avg_monthly_expenses,
    a.avg_savings_rate_percent,
    
    -- Net worth metrics
    COALESCE(n.year_end_net_worth, n.avg_annual_net_worth) AS year_end_net_worth,
    COALESCE(n.year_start_net_worth, n.avg_annual_net_worth) AS year_start_net_worth,
    n.annual_net_worth_change,
    n.year_end_total_assets,
    n.year_end_total_liabilities,
    n.peak_annual_net_worth,
    
    -- Mortgage progress
    COALESCE(n.year_start_mortgage_debt, 0) - COALESCE(n.year_end_mortgage_debt, 0) AS annual_mortgage_reduction,
    
    -- Savings metrics
    s.annual_total_savings,
    s.avg_annual_savings_rate,
    s.annual_liquid_savings,
    s.annual_investment_contributions,
    
    -- Cash flow metrics
    cf.annual_total_inflows,
    cf.annual_total_outflows,
    cf.avg_cash_flow_efficiency,
    cf.months_positive_cash_flow,
    cf.months_negative_cash_flow,
    
    -- Expense breakdowns
    a.annual_mortgage_expenses,
    a.annual_household_expenses,
    a.annual_food_expenses,
    a.annual_family_expenses,
    
    -- Performance ranges
    a.best_month_net_cash_flow,
    a.worst_month_net_cash_flow,
    s.best_month_savings_rate_pct,
    s.worst_month_savings_rate_pct,
    
    a.months_with_data,
    a.annual_transaction_count
    
  FROM annual_summary a
  LEFT JOIN net_worth_annual n ON a.comparison_year = n.comparison_year
  LEFT JOIN savings_annual s ON a.comparison_year = s.comparison_year  
  LEFT JOIN cash_flow_annual cf ON a.comparison_year = cf.comparison_year
),

year_over_year_comparisons AS (
  SELECT 
    *,
    -- Year-over-year changes
    LAG(annual_income) OVER (ORDER BY comparison_year) AS prev_year_income,
    LAG(annual_expenses) OVER (ORDER BY comparison_year) AS prev_year_expenses,
    LAG(year_end_net_worth) OVER (ORDER BY comparison_year) AS prev_year_end_net_worth,
    LAG(avg_annual_savings_rate) OVER (ORDER BY comparison_year) AS prev_year_savings_rate,
    
    -- Calculate percentage changes
    CASE 
      WHEN LAG(annual_income) OVER (ORDER BY comparison_year) > 0
      THEN ((annual_income - LAG(annual_income) OVER (ORDER BY comparison_year)) / 
            LAG(annual_income) OVER (ORDER BY comparison_year)) * 100
      ELSE NULL
    END AS yoy_income_change_percent,
    
    CASE 
      WHEN LAG(annual_expenses) OVER (ORDER BY comparison_year) > 0
      THEN ((annual_expenses - LAG(annual_expenses) OVER (ORDER BY comparison_year)) / 
            LAG(annual_expenses) OVER (ORDER BY comparison_year)) * 100
      ELSE NULL
    END AS yoy_expense_change_percent,
    
    CASE 
      WHEN LAG(year_end_net_worth) OVER (ORDER BY comparison_year) != 0
      THEN ((year_end_net_worth - LAG(year_end_net_worth) OVER (ORDER BY comparison_year)) / 
            ABS(LAG(year_end_net_worth) OVER (ORDER BY comparison_year))) * 100
      ELSE NULL
    END AS yoy_net_worth_change_percent,
    
    avg_annual_savings_rate - LAG(avg_annual_savings_rate) OVER (ORDER BY comparison_year) AS yoy_savings_rate_change,
    
    -- Absolute changes
    annual_income - LAG(annual_income) OVER (ORDER BY comparison_year) AS yoy_income_change,
    annual_expenses - LAG(annual_expenses) OVER (ORDER BY comparison_year) AS yoy_expense_change,
    year_end_net_worth - LAG(year_end_net_worth) OVER (ORDER BY comparison_year) AS yoy_net_worth_change,
    annual_total_savings - LAG(annual_total_savings) OVER (ORDER BY comparison_year) AS yoy_savings_change
    
  FROM combined_annual_metrics
),

final_scores AS (
  SELECT 
    *,
    -- Overall financial progress score (1-100)
    LEAST(100, GREATEST(0,
      50 + -- Base score
      (CASE WHEN yoy_income_change_percent > 0 THEN 10 ELSE 0 END) + -- Income growth bonus
      (CASE WHEN yoy_expense_change_percent < yoy_income_change_percent THEN 15 ELSE -5 END) + -- Expense control bonus
      (CASE WHEN yoy_net_worth_change_percent > 10 THEN 20 ELSE 0 END) + -- Net worth growth bonus
      (CASE WHEN yoy_savings_rate_change > 0 THEN 10 ELSE 0 END) + -- Savings improvement bonus
      (CASE WHEN months_positive_cash_flow >= 10 THEN 10 ELSE 0 END) -- Cash flow consistency bonus
    )) AS annual_financial_progress_score
  FROM year_over_year_comparisons
),

final_analysis AS (
  SELECT 
    *,
    -- Performance classifications
    CASE 
      WHEN yoy_income_change_percent > 10 THEN 'Strong Income Growth'
      WHEN yoy_income_change_percent > 3 THEN 'Moderate Income Growth'
      WHEN yoy_income_change_percent > -3 THEN 'Stable Income'
      ELSE 'Income Decline'
    END AS income_performance,
    
    CASE 
      WHEN yoy_expense_change_percent < 3 THEN 'Excellent Expense Control'
      WHEN yoy_expense_change_percent < 7 THEN 'Good Expense Control'
      WHEN yoy_expense_change_percent < 15 THEN 'Moderate Expense Growth'
      ELSE 'High Expense Growth'
    END AS expense_performance,
    
    CASE 
      WHEN yoy_net_worth_change_percent > 20 THEN 'Exceptional Net Worth Growth'
      WHEN yoy_net_worth_change_percent > 10 THEN 'Strong Net Worth Growth'
      WHEN yoy_net_worth_change_percent > 5 THEN 'Good Net Worth Growth'
      WHEN yoy_net_worth_change_percent > 0 THEN 'Modest Net Worth Growth'
      ELSE 'Net Worth Decline'
    END AS net_worth_performance,
    
    -- Key insights
    CASE 
      WHEN annual_financial_progress_score > 85 THEN 'Outstanding financial year - all metrics improving'
      WHEN annual_financial_progress_score > 70 THEN 'Strong financial year - most goals achieved'
      WHEN annual_financial_progress_score > 55 THEN 'Solid financial year - steady progress'
      WHEN annual_financial_progress_score > 40 THEN 'Mixed financial year - some areas need attention'
      ELSE 'Challenging financial year - focus on core improvements needed'
    END AS annual_financial_assessment,
    
    -- Top accomplishment
    CASE 
      WHEN yoy_net_worth_change_percent > 20 THEN 'Exceptional net worth growth of ' || ROUND(yoy_net_worth_change_percent, 1) || '%'
      WHEN yoy_savings_rate_change > 0.05 THEN 'Significant savings rate improvement of ' || ROUND(yoy_savings_rate_change * 100, 1) || ' percentage points'
      WHEN annual_mortgage_reduction > 10000 THEN 'Strong mortgage paydown of $' || ROUND(annual_mortgage_reduction, 0)
      WHEN yoy_income_change_percent > 15 THEN 'Excellent income growth of ' || ROUND(yoy_income_change_percent, 1) || '%'
      ELSE 'Maintained financial stability'
    END AS top_financial_accomplishment,
    
    -- Priority focus area for next year
    CASE 
      WHEN avg_annual_savings_rate < 0.10 THEN 'Increase savings rate to at least 10%'
      WHEN yoy_expense_change_percent > yoy_income_change_percent + 5 THEN 'Focus on expense management'
      WHEN months_negative_cash_flow > 3 THEN 'Improve cash flow consistency'
      WHEN annual_liquid_savings < annual_expenses * 0.25 THEN 'Build emergency fund'
      ELSE 'Optimize investment allocation and tax efficiency'
    END AS next_year_priority_focus,
    
    CURRENT_TIMESTAMP AS report_generated_at
    
  FROM final_scores
)

SELECT * FROM final_analysis
ORDER BY comparison_year DESC
