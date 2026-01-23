{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['budget_year_month'], 'unique': true},
      {'columns': ['transaction_year'], 'unique': false}
    ]
  )
}}

WITH base_monthly_account_balances AS (
  SELECT 
    ft.transaction_year,
    ft.transaction_month,
    ft.transaction_year || '-' || LPAD(ft.transaction_month::TEXT, 2, '0') AS budget_year_month,
    
    da.account_name,
    da.bank_name,
    da.account_type,
    da.account_category,
    da.is_liability,
    da.is_liquid_asset,
    da.is_mortgage,
    
    -- Get end of month balance for each account
    MAX(ft.account_balance) AS end_of_month_balance,
    MIN(ft.transaction_date) AS month_start_date,
    MAX(ft.transaction_date) AS month_end_date
    
  FROM {{ ref('fct_transactions') }} ft
  LEFT JOIN {{ ref('dim_accounts') }} da
    ON ft.account_key = da.account_key
  GROUP BY 
    ft.transaction_year,
    ft.transaction_month,
    da.account_name,
    da.bank_name,
    da.account_type,
    da.account_category,
    da.is_liability,
    da.is_liquid_asset,
    da.is_mortgage
),

monthly_account_balances AS (
  SELECT * FROM base_monthly_account_balances
  UNION ALL
  SELECT
    transaction_year,
    transaction_month,
    budget_year_month,
    account_name,
    bank_name,
    account_type,
    account_category,
    is_liability,
    is_liquid_asset,
    is_mortgage,
    end_of_month_balance,
    month_start_date,
    month_end_date
  FROM {{ ref('int_property_assets_monthly') }}
),

monthly_net_worth_calculation AS (
  SELECT 
    budget_year_month,
    transaction_year,
    transaction_month,
    
    -- Asset values (positive balances for assets, absolute value for display)
    SUM(CASE 
      WHEN NOT is_liability THEN end_of_month_balance 
      ELSE 0 
    END) AS total_assets,
    SUM(CASE 
      WHEN account_type = 'Property' THEN end_of_month_balance
      ELSE 0
    END) AS property_assets,
    SUM(CASE 
      WHEN NOT is_liability AND account_type <> 'Property' THEN end_of_month_balance
      ELSE 0
    END) AS non_property_assets,
    
    -- Liability values (negative balances for liabilities, show as positive for readability)
    SUM(CASE 
      WHEN is_liability THEN ABS(end_of_month_balance)
      ELSE 0 
    END) AS total_liabilities,
    
    -- Net worth calculation (assets - liabilities)
    SUM(CASE 
      WHEN NOT is_liability THEN end_of_month_balance 
      ELSE -ABS(end_of_month_balance)
    END) AS net_worth,
    
    -- Breakdown by account categories
    SUM(CASE 
      WHEN COALESCE(is_liquid_asset, FALSE) THEN end_of_month_balance 
      ELSE 0 
    END) AS liquid_assets,
    
    SUM(CASE 
      WHEN account_type = 'Offset' THEN end_of_month_balance 
      ELSE 0 
    END) AS offset_accounts,
    
    SUM(CASE 
      WHEN is_mortgage THEN ABS(end_of_month_balance)
      ELSE 0 
    END) AS mortgage_debt,
    
    SUM(CASE 
      WHEN is_liability AND NOT is_mortgage THEN ABS(end_of_month_balance)
      ELSE 0 
    END) AS other_debt,
    
    -- Account counts
    COUNT(CASE WHEN NOT is_liability THEN 1 END) AS asset_account_count,
    COUNT(CASE WHEN is_liability THEN 1 END) AS liability_account_count,
    
    MIN(month_start_date) AS period_start_date,
    MAX(month_end_date) AS period_end_date
    
  FROM monthly_account_balances
  GROUP BY budget_year_month, transaction_year, transaction_month
),

net_worth_trends AS (
  SELECT 
    *,
    -- Month-over-month changes
    LAG(net_worth) OVER (ORDER BY transaction_year, transaction_month) AS prev_month_net_worth,
    LAG(total_assets) OVER (ORDER BY transaction_year, transaction_month) AS prev_month_assets,
    LAG(total_liabilities) OVER (ORDER BY transaction_year, transaction_month) AS prev_month_liabilities,
    
    net_worth - LAG(net_worth) OVER (ORDER BY transaction_year, transaction_month) AS mom_net_worth_change,
    total_assets - LAG(total_assets) OVER (ORDER BY transaction_year, transaction_month) AS mom_assets_change,
    total_liabilities - LAG(total_liabilities) OVER (ORDER BY transaction_year, transaction_month) AS mom_liabilities_change,
    
    -- Percentage changes
    CASE 
      WHEN LAG(net_worth) OVER (ORDER BY transaction_year, transaction_month) != 0
      THEN ((net_worth - LAG(net_worth) OVER (ORDER BY transaction_year, transaction_month)) / 
            ABS(LAG(net_worth) OVER (ORDER BY transaction_year, transaction_month)))
      ELSE NULL
    END AS mom_net_worth_change_percent,
    
    -- Rolling averages (3 months)
    AVG(net_worth) OVER (
      ORDER BY transaction_year, transaction_month
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3m_avg_net_worth,
    
    AVG(total_assets) OVER (
      ORDER BY transaction_year, transaction_month
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3m_avg_assets,
    
    AVG(total_liabilities) OVER (
      ORDER BY transaction_year, transaction_month
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3m_avg_liabilities,
    
    -- Year-over-year comparisons (previous year's same month)
    LAG(net_worth, 1) OVER (
      PARTITION BY transaction_month
      ORDER BY transaction_year
    ) AS yoy_same_month_net_worth,
    
    -- Year-to-date progression
    net_worth - FIRST_VALUE(net_worth) OVER (
      PARTITION BY transaction_year 
      ORDER BY transaction_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS ytd_net_worth_change,
    
    -- January net worth for the same year
    FIRST_VALUE(net_worth) OVER (
      PARTITION BY transaction_year
      ORDER BY transaction_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS jan_net_worth_same_year
    
  FROM monthly_net_worth_calculation
),

net_worth_analysis AS (
  SELECT 
    *,
    (total_assets - property_assets - liquid_assets) AS other_assets,
    -- Financial ratios
    CASE WHEN total_assets > 0 THEN (total_liabilities / total_assets) ELSE 0 END AS debt_to_asset_ratio,
    CASE WHEN total_liabilities > 0 THEN (liquid_assets / total_liabilities) ELSE NULL END AS liquidity_ratio,
    CASE WHEN total_assets > 0 THEN (net_worth / total_assets) ELSE 0 END AS equity_ratio,
    
    -- Net worth growth analysis
    CASE 
      WHEN mom_net_worth_change > 0 THEN 'Increasing'
      WHEN mom_net_worth_change = 0 THEN 'Stable'
      ELSE 'Decreasing'
    END AS net_worth_trend_direction,
    
    -- Growth rate classification
    CASE 
      WHEN mom_net_worth_change_percent > 0.05 THEN 'Strong Growth'
      WHEN mom_net_worth_change_percent > 0.01 THEN 'Moderate Growth'
      WHEN mom_net_worth_change_percent > -0.01 THEN 'Stable'
      WHEN mom_net_worth_change_percent > -0.05 THEN 'Moderate Decline'
      ELSE 'Significant Decline'
    END AS growth_classification,
    
    -- Financial health indicators
    CASE 
      WHEN net_worth > 0 THEN 'Positive Net Worth'
      WHEN net_worth = 0 THEN 'Breakeven'
      ELSE 'Negative Net Worth'
    END AS financial_position,
    
    -- Mortgage progress (if applicable)
    CASE 
      WHEN mortgage_debt > 0 AND LAG(mortgage_debt) OVER (ORDER BY transaction_year, transaction_month) > 0
      THEN LAG(mortgage_debt) OVER (ORDER BY transaction_year, transaction_month) - mortgage_debt
      ELSE 0
    END AS monthly_mortgage_principal_reduction,
    
    -- Emergency fund assessment (liquid assets as months of potential expenses)
    -- Estimate monthly expenses as average decline in liquid assets when negative
    liquid_assets / NULLIF(GREATEST(1000, ABS(LEAST(0, mom_assets_change))), 0) AS estimated_months_expenses_covered,
    
    -- Year-over-year net worth change
    CASE 
      WHEN yoy_same_month_net_worth IS NOT NULL AND yoy_same_month_net_worth != 0
      THEN ((net_worth - yoy_same_month_net_worth) / ABS(yoy_same_month_net_worth))
      ELSE NULL
    END AS yoy_net_worth_change_percent,
    
    CURRENT_TIMESTAMP AS report_generated_at
    
  FROM net_worth_trends
),

allocation_analysis AS (
  SELECT
    *,
    -- Asset allocation percentages
    CASE WHEN total_assets > 0 THEN (liquid_assets / total_assets) ELSE 0 END AS liquid_asset_allocation_pct,
    CASE WHEN total_assets > 0 THEN (property_assets / total_assets) ELSE 0 END AS property_asset_allocation_pct,
    CASE WHEN total_assets > 0 THEN (other_assets / total_assets) ELSE 0 END AS other_asset_allocation_pct,

    -- Ideal allocations (60% liquid, 35% property, 5% other for balanced portfolio)
    0.60 AS ideal_liquid_allocation,
    0.35 AS ideal_property_allocation,
    0.05 AS ideal_other_allocation,

    -- Allocation drift (difference from ideal, as percentages)
    (CASE WHEN total_assets > 0 THEN (liquid_assets / total_assets) ELSE 0 END) - 0.60 AS liquid_allocation_drift,
    (CASE WHEN total_assets > 0 THEN (property_assets / total_assets) ELSE 0 END) - 0.35 AS property_allocation_drift,
    (CASE WHEN total_assets > 0 THEN (other_assets / total_assets) ELSE 0 END) - 0.05 AS other_allocation_drift,

    -- Overall allocation health (sum of absolute drift values, lower is better)
    ABS((CASE WHEN total_assets > 0 THEN (liquid_assets / total_assets) ELSE 0 END) - 0.60) +
    ABS((CASE WHEN total_assets > 0 THEN (property_assets / total_assets) ELSE 0 END) - 0.35) +
    ABS((CASE WHEN total_assets > 0 THEN (other_assets / total_assets) ELSE 0 END) - 0.05) AS total_allocation_drift_score
  FROM net_worth_analysis
),

final_insights AS (
  SELECT
    *,
    -- Net worth health score (1-100)
    LEAST(100, GREATEST(0,
      50 + -- Base score
      (CASE WHEN net_worth > 0 THEN 20 ELSE -20 END) + -- Positive net worth bonus
      (CASE WHEN debt_to_asset_ratio < 0.5 THEN 15 ELSE -10 END) + -- Low debt ratio bonus (ratio scale)
      (CASE WHEN mom_net_worth_change > 0 THEN 10 ELSE 0 END) + -- Growth bonus
      (CASE WHEN liquidity_ratio > 0.2 THEN 5 ELSE 0 END) -- Liquidity bonus (ratio scale)
    )) AS net_worth_health_score,

    -- Financial advice
    CASE
      WHEN net_worth < 0 AND debt_to_asset_ratio > 0.8 THEN 'Focus on debt reduction immediately'
      WHEN liquid_assets < 1000 THEN 'Build emergency fund before investing'
      WHEN debt_to_asset_ratio > 0.7 THEN 'Consider debt consolidation or aggressive paydown'
      WHEN net_worth > 0 AND mom_net_worth_change > 0 THEN 'Strong financial position - consider growth investments'
      WHEN estimated_months_expenses_covered > 6 THEN 'Good liquidity - explore investment opportunities'
      ELSE 'Monitor trends and maintain current strategy'
    END AS financial_advice,

    -- Milestone tracking
    CASE
      WHEN net_worth >= 100000 THEN 'Six-Figure Net Worth Achieved'
      WHEN net_worth >= 50000 THEN 'Building Wealth Steadily'
      WHEN net_worth >= 10000 THEN 'Positive Momentum'
      WHEN net_worth >= 0 THEN 'Breaking Even'
      ELSE 'Rebuilding Phase'
    END AS wealth_milestone,

    -- Progress toward goals (assuming goal is positive net worth growth)
    CASE
      WHEN yoy_net_worth_change_percent > 0.10 THEN 'Exceeding Expectations'
      WHEN yoy_net_worth_change_percent > 0.05 THEN 'On Track'
      WHEN yoy_net_worth_change_percent > 0 THEN 'Slow Progress'
      ELSE 'Below Expectations'
    END AS annual_progress_assessment

  FROM allocation_analysis
)

SELECT * FROM final_insights
WHERE period_end_date < date_trunc('month', CURRENT_DATE)
ORDER BY transaction_year DESC, transaction_month DESC
