{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['budget_year_month'], 'unique': true},
      {'columns': ['transaction_year'], 'unique': false}
    ]
  )
}}

WITH monthly_budget_baseline AS (
  SELECT
    budget_year_month,
    CAST(SPLIT_PART(budget_year_month, '-', 1) AS BIGINT) AS transaction_year,
    CAST(SPLIT_PART(budget_year_month, '-', 2) AS BIGINT) AS transaction_month,
    COALESCE(total_income, 0) AS total_income,
    COALESCE(total_expenses, 0) AS total_expenses,
    COALESCE(net_cash_flow, 0) AS net_cash_flow
  FROM {{ ref('rpt_monthly_budget_summary') }}
),

monthly_savings_components AS (
  SELECT
    ft.transaction_year,
    ft.transaction_month,
    ft.transaction_year || '-' || LPAD(ft.transaction_month::TEXT, 2, '0') AS budget_year_month,
    ft.transaction_amount,
    da.account_type,
    da.is_liquid_asset,
    da.is_transactional,
    da.is_mortgage,
    dc.level_1_category,
    (
      COALESCE(ft.transaction_memo, '') ILIKE '%VANGUARD%'
      OR COALESCE(ft.transaction_description, '') ILIKE '%VANGUARD%'
      OR COALESCE(ft.transaction_memo, '') ILIKE '%SELFWEALTH%'
      OR COALESCE(ft.transaction_description, '') ILIKE '%SELFWEALTH%'
    ) AS is_vanguard_share_txn,

    CASE
      -- Offset increases represent cash being parked against the home loan.
      WHEN da.account_type = 'Offset' AND ft.transaction_amount > 0 THEN 'Offset_Savings'

      -- Cash savings excludes transactional day-to-day accounts.
      WHEN da.is_liquid_asset
           AND COALESCE(da.account_type, '') <> 'Offset'
           AND NOT COALESCE(da.is_transactional, TRUE)
           AND ft.transaction_amount > 0 THEN 'Cash_Savings'

      WHEN da.is_mortgage AND ft.transaction_amount < 0 THEN 'Mortgage_Payment'

      -- Vanguard is treated as share-account investing; outbound only avoids mirrored receipt double-counts.
      WHEN (
        COALESCE(ft.transaction_memo, '') ILIKE '%VANGUARD%'
        OR COALESCE(ft.transaction_description, '') ILIKE '%VANGUARD%'
        OR COALESCE(ft.transaction_memo, '') ILIKE '%SELFWEALTH%'
        OR COALESCE(ft.transaction_description, '') ILIKE '%SELFWEALTH%'
      ) AND ft.transaction_amount < 0 THEN 'Investment_Share_Account'

      WHEN dc.level_1_category ILIKE '%Investment%' AND ft.transaction_amount < 0 THEN 'Investment'
      ELSE 'Other'
    END AS transaction_classification
  FROM {{ ref('fct_transactions') }} ft
  LEFT JOIN {{ ref('dim_accounts') }} da
    ON ft.account_key = da.account_key
  LEFT JOIN {{ ref('dim_categories') }} dc
    ON ft.category_key = dc.category_key
),

monthly_savings_calculation AS (
  SELECT
    budget_year_month,
    transaction_year,
    transaction_month,

    SUM(CASE
      WHEN transaction_classification = 'Offset_Savings' THEN ABS(transaction_amount)
      ELSE 0
    END) AS offset_savings,

    SUM(CASE
      WHEN transaction_classification = 'Cash_Savings' THEN ABS(transaction_amount)
      ELSE 0
    END) AS cash_savings,

    SUM(CASE
      WHEN transaction_classification IN ('Investment', 'Investment_Share_Account') THEN ABS(transaction_amount)
      ELSE 0
    END) AS investment_contributions,

    SUM(CASE
      WHEN transaction_classification = 'Mortgage_Payment' THEN ABS(transaction_amount)
      ELSE 0
    END) AS mortgage_payments,

    -- Estimate 80% of mortgage payment goes to principal (rough estimate)
    SUM(CASE
      WHEN transaction_classification = 'Mortgage_Payment' THEN ABS(transaction_amount) * 0.8
      ELSE 0
    END) AS estimated_mortgage_principal_payment
  FROM monthly_savings_components
  WHERE transaction_classification != 'Other'
  GROUP BY budget_year_month, transaction_year, transaction_month
),

savings_metrics AS (
  SELECT
    mb.budget_year_month,
    mb.transaction_year,
    mb.transaction_month,
    mb.total_income,
    mb.total_expenses,
    mb.net_cash_flow AS total_savings,
    mb.net_cash_flow,
    COALESCE(msc.offset_savings, 0) AS offset_savings,
    COALESCE(msc.cash_savings, 0) AS cash_savings,
    COALESCE(msc.investment_contributions, 0) AS investment_contributions,
    COALESCE(msc.mortgage_payments, 0) AS mortgage_payments,
    COALESCE(msc.estimated_mortgage_principal_payment, 0) AS estimated_mortgage_principal_payment,

    -- Traditional savings rate (ratio, excluding mortgage principal)
    CASE
      WHEN mb.total_income > 0
      THEN ((COALESCE(msc.offset_savings, 0) + COALESCE(msc.cash_savings, 0) + COALESCE(msc.investment_contributions, 0)) / mb.total_income)
      ELSE 0
    END AS traditional_savings_rate_percent,

    -- Primary KPI: net cash flow savings rate.
    CASE
      WHEN mb.total_income > 0
      THEN (mb.net_cash_flow / mb.total_income)
      ELSE 0
    END AS total_savings_rate_percent,

    -- Expense ratio (ratio)
    CASE
      WHEN mb.total_income > 0
      THEN (mb.total_expenses / mb.total_income)
      ELSE 0
    END AS expense_ratio_percent,

    -- Cash savings rate (liquid savings only, ratio 0-1)
    CASE
      WHEN mb.total_income > 0
      THEN ((COALESCE(msc.cash_savings, 0) + COALESCE(msc.offset_savings, 0)) / mb.total_income)
      ELSE 0
    END AS liquid_savings_rate_percent,

    -- Investment rate (ratio 0-1)
    CASE
      WHEN mb.total_income > 0
      THEN (COALESCE(msc.investment_contributions, 0) / mb.total_income)
      ELSE 0
    END AS investment_rate_percent
  FROM monthly_budget_baseline mb
  LEFT JOIN monthly_savings_calculation msc
    ON mb.budget_year_month = msc.budget_year_month
),

savings_trends AS (
  SELECT 
    *,
    -- Month-over-month comparisons
    LAG(total_savings_rate_percent) OVER (ORDER BY transaction_year, transaction_month) AS prev_month_savings_rate,
    LAG(total_savings) OVER (ORDER BY transaction_year, transaction_month) AS prev_month_total_savings,
    LAG(total_income) OVER (ORDER BY transaction_year, transaction_month) AS prev_month_income,
    
    -- Changes
    total_savings_rate_percent - LAG(total_savings_rate_percent) OVER (ORDER BY transaction_year, transaction_month) AS mom_savings_rate_change,
    total_savings - LAG(total_savings) OVER (ORDER BY transaction_year, transaction_month) AS mom_savings_change,
    
    -- Rolling averages (3 months)
    AVG(total_savings_rate_percent) OVER (
      ORDER BY transaction_year, transaction_month
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3m_avg_savings_rate,
    
    AVG(total_savings) OVER (
      ORDER BY transaction_year, transaction_month
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3m_avg_savings_amount,
    
    AVG(traditional_savings_rate_percent) OVER (
      ORDER BY transaction_year, transaction_month
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3m_avg_traditional_savings_rate,
    
    -- Year-to-date accumulation
    SUM(total_savings) OVER (
      PARTITION BY transaction_year 
      ORDER BY transaction_month
    ) AS ytd_total_savings,
    
    SUM(total_income) OVER (
      PARTITION BY transaction_year
      ORDER BY transaction_month  
    ) AS ytd_total_income,
    
    -- Year-to-date savings rate (ratio)
    CASE 
      WHEN SUM(total_income) OVER (PARTITION BY transaction_year ORDER BY transaction_month) > 0
      THEN (SUM(total_savings) OVER (PARTITION BY transaction_year ORDER BY transaction_month) / 
            SUM(total_income) OVER (PARTITION BY transaction_year ORDER BY transaction_month))
      ELSE 0
    END AS ytd_savings_rate_percent,
    
    -- Year-over-year comparisons
    LAG(total_savings_rate_percent, 12) OVER (
      PARTITION BY transaction_month
      ORDER BY transaction_year
    ) AS yoy_same_month_savings_rate
    
  FROM savings_metrics
),

savings_analysis AS (
  SELECT 
    *,
    -- Savings performance classification (ratio thresholds)
    CASE 
      WHEN total_savings_rate_percent >= 0.30 THEN 'Exceptional Saver (30%+)'
      WHEN total_savings_rate_percent >= 0.20 THEN 'Strong Saver (20-30%)'
      WHEN total_savings_rate_percent >= 0.15 THEN 'Good Saver (15-20%)'
      WHEN total_savings_rate_percent >= 0.10 THEN 'Average Saver (10-15%)'
      WHEN total_savings_rate_percent >= 0.05 THEN 'Low Saver (5-10%)'
      ELSE 'Minimal Savings (<5%)'
    END AS savings_performance_tier,
    
    -- Trend analysis (ratio thresholds)
    CASE 
      WHEN mom_savings_rate_change > 0.02 THEN 'Improving Significantly'
      WHEN mom_savings_rate_change > 0.005 THEN 'Improving'
      WHEN mom_savings_rate_change > -0.005 THEN 'Stable'
      WHEN mom_savings_rate_change > -0.02 THEN 'Declining'
      ELSE 'Declining Significantly'
    END AS savings_trend,
    
    -- Savings consistency (based on variance from rolling average)
    ABS(total_savings_rate_percent - rolling_3m_avg_savings_rate) AS savings_rate_volatility,
    
    CASE 
      WHEN ABS(total_savings_rate_percent - rolling_3m_avg_savings_rate) < 0.02 THEN 'Very Consistent'
      WHEN ABS(total_savings_rate_percent - rolling_3m_avg_savings_rate) < 0.05 THEN 'Consistent'
      WHEN ABS(total_savings_rate_percent - rolling_3m_avg_savings_rate) < 0.10 THEN 'Somewhat Variable'
      ELSE 'Highly Variable'
    END AS savings_consistency,
    
    -- Financial goals progress (various benchmarks)
    CASE 
      WHEN traditional_savings_rate_percent >= 0.20 THEN 'Meeting FIRE Target (20%+)'
      WHEN traditional_savings_rate_percent >= 0.15 THEN 'Exceeding Standard Target (15%+)'
      WHEN traditional_savings_rate_percent >= 0.10 THEN 'Meeting Standard Target (10%+)'
      ELSE 'Below Standard Target (<10%)'
    END AS savings_goal_progress,
    
    -- Emergency fund assessment (based on liquid savings accumulation)
    (cash_savings + offset_savings) * 12 AS estimated_annual_liquid_savings,
    
    -- Year-over-year improvement
    CASE 
      WHEN yoy_same_month_savings_rate IS NOT NULL
      THEN total_savings_rate_percent - yoy_same_month_savings_rate
      ELSE NULL
    END AS yoy_savings_rate_improvement,
    
    CURRENT_TIMESTAMP AS report_generated_at
    
  FROM savings_trends
),

final_insights AS (
  SELECT 
    *,
    -- Alias for Grafana panel to apply USD unit explicitly
    estimated_annual_liquid_savings AS estimated_annual_liquid_savings_usd,
    -- Savings health score (1-100)
    LEAST(100, GREATEST(0,
      CASE 
        WHEN total_savings_rate_percent >= 0.30 THEN 95
        WHEN total_savings_rate_percent >= 0.25 THEN 90
        WHEN total_savings_rate_percent >= 0.20 THEN 80
        WHEN total_savings_rate_percent >= 0.15 THEN 70
        WHEN total_savings_rate_percent >= 0.10 THEN 60
        WHEN total_savings_rate_percent >= 0.05 THEN 40
        ELSE 20
      END +
      (CASE WHEN mom_savings_rate_change > 0 THEN 5 ELSE 0 END) + -- Improvement bonus
      (CASE WHEN savings_consistency IN ('Very Consistent', 'Consistent') THEN 5 ELSE 0 END) -- Consistency bonus
    )) AS savings_health_score,
    
    -- Personalized recommendations
    CASE 
      WHEN total_savings_rate_percent < 0.05 THEN 'Critical: Optimize offset savings strategy - review offset balance allocation'
      WHEN traditional_savings_rate_percent < 0.10 AND expense_ratio_percent > 0.90 THEN 'Focus on reducing expenses to increase savings'
      WHEN liquid_savings_rate_percent < 0.05 THEN 'Build emergency fund before other investments'
      WHEN investment_rate_percent < 0.05 AND total_savings_rate_percent > 0.15 THEN 'Consider increasing investment contributions'
      WHEN total_savings_rate_percent > 0.25 THEN 'Excellent savings rate - explore tax optimization strategies'
      WHEN savings_consistency = 'Highly Variable' THEN 'Work on making savings more consistent monthly'
      ELSE 'Maintain current savings momentum and look for optimization opportunities'
    END AS savings_recommendation,
    
    -- Time to financial milestones (rough estimates)
    CASE 
      WHEN total_savings > 0 AND total_savings_rate_percent > 0
      THEN ROUND((50000 / (total_savings * 12))::NUMERIC, 1) -- Years to $50k at current rate
      ELSE NULL
    END AS estimated_years_to_50k,
    
    -- Monthly savings target to reach standard 15% rate
    CASE
      WHEN total_income > 0 AND traditional_savings_rate_percent < 0.15
      THEN (total_income * 0.15) - (cash_savings + offset_savings + investment_contributions)
      ELSE 0
    END AS additional_monthly_savings_needed_for_15_percent,

    -- Goal tracking: Monthly savings needed for specific milestones
    -- Goal 1: 20% Savings Rate (intermediate milestone)
    CASE
      WHEN total_income > 0 AND traditional_savings_rate_percent < 0.20
      THEN GREATEST(0, (total_income * 0.20) - (cash_savings + offset_savings + investment_contributions))
      ELSE 0
    END AS monthly_savings_needed_for_20_percent,

    -- Goal 2: FIRE Target (25% savings rate)
    CASE
      WHEN total_income > 0 AND traditional_savings_rate_percent < 0.25
      THEN GREATEST(0, (total_income * 0.25) - (cash_savings + offset_savings + investment_contributions))
      ELSE 0
    END AS monthly_savings_needed_for_fire,

    -- Progress to 20% goal (percentage, 0-1 ratio)
    CASE
      WHEN total_income > 0 AND total_income * 0.20 > 0
      THEN LEAST(1.0, GREATEST(0.0, ((cash_savings + offset_savings + investment_contributions) / (total_income * 0.20))))
      ELSE 0
    END AS progress_to_20_percent_goal,

    -- Progress to 25% FIRE goal (percentage, 0-1 ratio)
    CASE
      WHEN total_income > 0 AND total_income * 0.25 > 0
      THEN LEAST(1.0, GREATEST(0.0, ((cash_savings + offset_savings + investment_contributions) / (total_income * 0.25))))
      ELSE 0
    END AS progress_to_fire_goal,

    -- Benchmark status against common targets
    CASE
      WHEN traditional_savings_rate_percent >= 0.25 THEN 'Exceeds FIRE Target (25%+)'
      WHEN traditional_savings_rate_percent >= 0.20 THEN 'Meets Premium Goal (20%+)'
      WHEN traditional_savings_rate_percent >= 0.15 THEN 'Meets Standard Target (15%+)'
      WHEN traditional_savings_rate_percent >= 0.10 THEN 'Below Benchmark (10%)'
      ELSE 'Critical: Plan Needed (<10%)'
    END AS benchmark_status,

    -- Action priority items (comma-separated for display)
    CASE
      WHEN traditional_savings_rate_percent < 0.10 THEN 'Optimize offset savings strategy | Review all expense categories | Build emergency fund'
      WHEN traditional_savings_rate_percent < 0.15 THEN 'Increase savings rate by 5% | Cut discretionary spending | Automate transfers'
      WHEN traditional_savings_rate_percent < 0.20 THEN 'Boost savings toward 20% | Optimize investment allocation | Review recurring bills'
      WHEN traditional_savings_rate_percent < 0.25 THEN 'Scale toward FIRE target | Tax-optimize investments | Increase income'
      ELSE 'Maintain 25% rate | Evaluate wealth protection | Plan wealth distribution'
    END AS action_priorities

  FROM savings_analysis
)

SELECT * FROM final_insights
WHERE to_date(budget_year_month || '-01', 'YYYY-MM-DD') < date_trunc('month', CURRENT_DATE)
ORDER BY transaction_year DESC, transaction_month DESC
