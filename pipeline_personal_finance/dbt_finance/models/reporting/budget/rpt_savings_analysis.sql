{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['budget_year_month'], 'unique': true},
      {'columns': ['transaction_year'], 'unique': false}
    ]
  )
}}

WITH monthly_savings_components AS (
  SELECT 
    ft.transaction_year,
    ft.transaction_month,
    ft.transaction_year || '-' || LPAD(ft.transaction_month::TEXT, 2, '0') AS budget_year_month,
    
    da.account_type,
    da.account_category,
    da.is_liability,
    da.is_mortgage,
    ft.is_income_transaction,
    ft.is_internal_transfer,
    dc.level_1_category,
    ft.transaction_amount,
    
    -- Classify savings types
    CASE 
      WHEN da.account_type = 'Offset' AND ft.transaction_amount > 0 THEN 'Offset_Savings'
      WHEN da.account_type IN ('Bills Account', 'Everyday Account') AND ft.transaction_amount > 0 
           AND NOT ft.is_income_transaction AND NOT ft.is_internal_transfer THEN 'Cash_Savings'
      WHEN ft.is_income_transaction THEN 'Income'
      WHEN da.is_mortgage AND ft.transaction_amount < 0 THEN 'Mortgage_Payment'
      WHEN dc.level_1_category LIKE '%Investment%' OR da.account_name LIKE '%invest%' THEN 'Investment'
      WHEN NOT ft.is_internal_transfer AND NOT ft.is_income_transaction AND ft.transaction_amount < 0 THEN 'Expense'
      ELSE 'Other'
    END AS transaction_classification
    
  FROM {{ ref('fct_transactions_enhanced') }} ft
  LEFT JOIN {{ ref('dim_accounts_enhanced') }} da
    ON ft.account_key = da.account_key
  LEFT JOIN {{ ref('dim_categories_enhanced') }} dc
    ON ft.category_key = dc.category_key
),

monthly_savings_calculation AS (
  SELECT 
    budget_year_month,
    transaction_year,
    transaction_month,
    
    -- Income components
    SUM(CASE 
      WHEN transaction_classification = 'Income' THEN ABS(transaction_amount) 
      ELSE 0 
    END) AS total_income,
    
    -- Expense components  
    SUM(CASE 
      WHEN transaction_classification = 'Expense' THEN ABS(transaction_amount)
      ELSE 0 
    END) AS total_expenses,
    
    -- Savings components
    SUM(CASE 
      WHEN transaction_classification = 'Offset_Savings' THEN ABS(transaction_amount)
      ELSE 0 
    END) AS offset_savings,
    
    SUM(CASE 
      WHEN transaction_classification = 'Cash_Savings' THEN ABS(transaction_amount)
      ELSE 0 
    END) AS cash_savings,
    
    SUM(CASE 
      WHEN transaction_classification = 'Investment' AND transaction_amount < 0 THEN ABS(transaction_amount)
      ELSE 0 
    END) AS investment_contributions,
    
    -- Debt payments (excluding regular mortgage payments)
    SUM(CASE 
      WHEN transaction_classification = 'Mortgage_Payment' THEN ABS(transaction_amount)
      ELSE 0 
    END) AS mortgage_payments,
    
    -- Calculate forced savings from mortgage principal payments
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
    *,
    -- Total savings calculations
    offset_savings + cash_savings + investment_contributions + estimated_mortgage_principal_payment AS total_savings,
    
    -- Net worth change (approximation based on cash flow)
    total_income - total_expenses AS net_cash_flow,
    
    -- Traditional savings rate (ratio, excluding mortgage principal)
    CASE 
      WHEN total_income > 0 
      THEN ((offset_savings + cash_savings + investment_contributions) / total_income)
      ELSE 0 
    END AS traditional_savings_rate_percent,
    
    -- Total savings rate (ratio, including mortgage principal as forced savings)
    CASE 
      WHEN total_income > 0 
      THEN ((offset_savings + cash_savings + investment_contributions + estimated_mortgage_principal_payment) / total_income)
      ELSE 0 
    END AS total_savings_rate_percent,
    
    -- Expense ratio (ratio)
    CASE 
      WHEN total_income > 0 
      THEN (total_expenses / total_income)
      ELSE 0 
    END AS expense_ratio_percent,
    
    -- Cash savings rate (liquid savings only)
    CASE 
      WHEN total_income > 0 
      THEN ((cash_savings + offset_savings) / total_income) * 100
      ELSE 0 
    END AS liquid_savings_rate_percent,
    
    -- Investment rate
    CASE 
      WHEN total_income > 0 
      THEN (investment_contributions / total_income) * 100
      ELSE 0 
    END AS investment_rate_percent
    
  FROM monthly_savings_calculation
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
    -- Savings performance classification
    CASE 
      WHEN total_savings_rate_percent >= 30 THEN 'Exceptional Saver (30%+)'
      WHEN total_savings_rate_percent >= 20 THEN 'Strong Saver (20-30%)'
      WHEN total_savings_rate_percent >= 15 THEN 'Good Saver (15-20%)'
      WHEN total_savings_rate_percent >= 10 THEN 'Average Saver (10-15%)'
      WHEN total_savings_rate_percent >= 5 THEN 'Low Saver (5-10%)'
      ELSE 'Minimal Savings (<5%)'
    END AS savings_performance_tier,
    
    -- Trend analysis
    CASE 
      WHEN mom_savings_rate_change > 2 THEN 'Improving Significantly'
      WHEN mom_savings_rate_change > 0.5 THEN 'Improving'
      WHEN mom_savings_rate_change > -0.5 THEN 'Stable'
      WHEN mom_savings_rate_change > -2 THEN 'Declining'
      ELSE 'Declining Significantly'
    END AS savings_trend,
    
    -- Savings consistency (based on variance from rolling average)
    ABS(total_savings_rate_percent - rolling_3m_avg_savings_rate) AS savings_rate_volatility,
    
    CASE 
      WHEN ABS(total_savings_rate_percent - rolling_3m_avg_savings_rate) < 2 THEN 'Very Consistent'
      WHEN ABS(total_savings_rate_percent - rolling_3m_avg_savings_rate) < 5 THEN 'Consistent'
      WHEN ABS(total_savings_rate_percent - rolling_3m_avg_savings_rate) < 10 THEN 'Somewhat Variable'
      ELSE 'Highly Variable'
    END AS savings_consistency,
    
    -- Financial goals progress (various benchmarks)
    CASE 
      WHEN traditional_savings_rate_percent >= 20 THEN 'Meeting FIRE Target (20%+)'
      WHEN traditional_savings_rate_percent >= 15 THEN 'Exceeding Standard Target (15%+)'
      WHEN traditional_savings_rate_percent >= 10 THEN 'Meeting Standard Target (10%+)'
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
    -- Savings health score (1-100)
    LEAST(100, GREATEST(0,
      CASE 
        WHEN total_savings_rate_percent >= 30 THEN 95
        WHEN total_savings_rate_percent >= 25 THEN 90
        WHEN total_savings_rate_percent >= 20 THEN 80
        WHEN total_savings_rate_percent >= 15 THEN 70
        WHEN total_savings_rate_percent >= 10 THEN 60
        WHEN total_savings_rate_percent >= 5 THEN 40
        ELSE 20
      END +
      (CASE WHEN mom_savings_rate_change > 0 THEN 5 ELSE 0 END) + -- Improvement bonus
      (CASE WHEN savings_consistency IN ('Very Consistent', 'Consistent') THEN 5 ELSE 0 END) -- Consistency bonus
    )) AS savings_health_score,
    
    -- Personalized recommendations
    CASE 
      WHEN total_savings_rate_percent < 5 THEN 'Critical: Create basic savings plan - start with 1% of income'
      WHEN traditional_savings_rate_percent < 10 AND expense_ratio_percent > 90 THEN 'Focus on reducing expenses to increase savings'
      WHEN liquid_savings_rate_percent < 5 THEN 'Build emergency fund before other investments'
      WHEN investment_rate_percent < 5 AND total_savings_rate_percent > 15 THEN 'Consider increasing investment contributions'
      WHEN total_savings_rate_percent > 25 THEN 'Excellent savings rate - explore tax optimization strategies'
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
      WHEN total_income > 0 AND traditional_savings_rate_percent < 15
      THEN (total_income * 0.15) - (cash_savings + offset_savings + investment_contributions)
      ELSE 0
    END AS additional_monthly_savings_needed_for_15_percent
    
  FROM savings_analysis
)

SELECT * FROM final_insights
ORDER BY transaction_year DESC, transaction_month DESC
