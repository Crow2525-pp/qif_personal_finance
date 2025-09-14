{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['budget_year_month', 'account_name'], 'unique': false},
      {'columns': ['account_name'], 'unique': false}
    ]
  )
}}

WITH monthly_account_activity AS (
  SELECT 
    ft.transaction_year,
    ft.transaction_month,
    ft.transaction_year || '-' || LPAD(ft.transaction_month::TEXT, 2, '0') AS budget_year_month,
    
    da.account_name,
    da.bank_name,
    da.account_type,
    da.account_category,
    da.is_liability,
    da.is_transactional,
    da.is_mortgage,
    
    -- Transaction activity
    COUNT(*) AS total_transactions,
    SUM(ft.transaction_amount) AS net_activity,
    SUM(CASE WHEN ft.transaction_amount > 0 THEN ft.transaction_amount ELSE 0 END) AS total_credits,
    SUM(CASE WHEN ft.transaction_amount < 0 THEN ABS(ft.transaction_amount) ELSE 0 END) AS total_debits,
    COUNT(CASE WHEN ft.transaction_amount > 0 THEN 1 END) AS credit_transaction_count,
    COUNT(CASE WHEN ft.transaction_amount < 0 THEN 1 END) AS debit_transaction_count,
    
    -- Balance information (end of month balance)
    MAX(ft.account_balance) AS end_of_month_balance,
    MIN(ft.account_balance) AS min_month_balance,
    MAX(ft.account_balance) - MIN(ft.account_balance) AS balance_range,
    
    AVG(ft.transaction_amount) AS avg_transaction_amount,
    STDDEV(ft.transaction_amount) AS transaction_volatility
    
  FROM {{ ref('fct_transactions_enhanced') }} ft
  LEFT JOIN {{ ref('dim_accounts_enhanced') }} da
    ON ft.account_key = da.account_key
  GROUP BY 
    ft.transaction_year,
    ft.transaction_month,
    da.account_name,
    da.bank_name,
    da.account_type,
    da.account_category,
    da.is_liability,
    da.is_transactional,
    da.is_mortgage
),

account_trends AS (
  SELECT 
    *,
    -- Month-over-month balance change
    end_of_month_balance - LAG(end_of_month_balance) OVER (
      PARTITION BY account_name 
      ORDER BY transaction_year, transaction_month
    ) AS mom_balance_change,
    
    -- Percentage balance change
    CASE 
      WHEN LAG(end_of_month_balance) OVER (
        PARTITION BY account_name 
        ORDER BY transaction_year, transaction_month
      ) != 0
      THEN ((end_of_month_balance - LAG(end_of_month_balance) OVER (
        PARTITION BY account_name 
        ORDER BY transaction_year, transaction_month
      )) / ABS(LAG(end_of_month_balance) OVER (
        PARTITION BY account_name 
        ORDER BY transaction_year, transaction_month
      )))
      ELSE NULL
    END AS mom_balance_change_percent,
    
    -- Rolling averages
    AVG(end_of_month_balance) OVER (
      PARTITION BY account_name
      ORDER BY transaction_year, transaction_month
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3m_avg_balance,
    
    AVG(net_activity) OVER (
      PARTITION BY account_name
      ORDER BY transaction_year, transaction_month
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3m_avg_net_activity,
    
    -- Year-over-year comparisons
    LAG(end_of_month_balance, 12) OVER (
      PARTITION BY account_name, transaction_month
      ORDER BY transaction_year
    ) AS yoy_same_month_balance,
    
    -- Account utilization (for credit accounts)
    CASE 
      WHEN account_type IN ('Bills Account', 'Everyday Account') AND end_of_month_balance > 0
      THEN (total_debits / NULLIF(end_of_month_balance, 0))
      ELSE NULL
    END AS account_utilization_ratio
    
  FROM monthly_account_activity
),

account_performance_metrics AS (
  SELECT 
    *,
    -- Performance classifications
    CASE 
      WHEN is_mortgage AND mom_balance_change < 0 THEN 'Mortgage Reducing (Good)'
      WHEN is_mortgage AND mom_balance_change > 0 THEN 'Mortgage Increasing (Concern)'
      WHEN NOT is_mortgage AND is_liability AND mom_balance_change < 0 THEN 'Debt Reducing (Good)'
      WHEN NOT is_mortgage AND is_liability AND mom_balance_change > 0 THEN 'Debt Increasing (Concern)'
      WHEN NOT is_liability AND mom_balance_change > 0 THEN 'Savings Growing (Good)'
      WHEN NOT is_liability AND mom_balance_change < 0 THEN 'Savings Decreasing'
      ELSE 'Stable'
    END AS balance_trend_analysis,
    
    -- Account health score (1-100)
    CASE 
      WHEN is_mortgage THEN 
        LEAST(100, GREATEST(0, 
          50 + -- Base score
          (CASE WHEN mom_balance_change <= 0 THEN 30 ELSE -20 END) + -- Reward mortgage reduction
          (CASE WHEN total_transactions BETWEEN 1 AND 5 THEN 20 ELSE 0 END) -- Reward normal activity
        ))
      WHEN is_liability THEN
        LEAST(100, GREATEST(0,
          50 + -- Base score  
          (CASE WHEN mom_balance_change <= 0 THEN 40 ELSE -30 END) + -- Reward debt reduction
          (CASE WHEN ABS(end_of_month_balance) < 1000 THEN 10 ELSE 0 END) -- Bonus for low balances
        ))
      ELSE -- Asset accounts
        LEAST(100, GREATEST(0,
          50 + -- Base score
          (CASE WHEN mom_balance_change >= 0 THEN 30 ELSE -10 END) + -- Reward growth
          (CASE WHEN end_of_month_balance > rolling_3m_avg_balance THEN 20 ELSE 0 END) -- Above average bonus
        ))
    END AS account_health_score,
    
    -- Activity level classification
    CASE 
      WHEN total_transactions = 0 THEN 'Inactive'
      WHEN total_transactions <= 5 THEN 'Low Activity'
      WHEN total_transactions <= 20 THEN 'Moderate Activity'
      WHEN total_transactions <= 50 THEN 'High Activity'
      ELSE 'Very High Activity'
    END AS activity_level,
    
    -- Balance trend over last 3 months
    CASE 
      WHEN end_of_month_balance > rolling_3m_avg_balance * 1.05 THEN 'Above Average'
      WHEN end_of_month_balance < rolling_3m_avg_balance * 0.95 THEN 'Below Average' 
      ELSE 'Near Average'
    END AS balance_vs_trend,
    
    CURRENT_TIMESTAMP AS report_generated_at
    
  FROM account_trends
),

final_insights AS (
  SELECT 
    *,
    -- Add quarterly and annual summaries
    SUM(net_activity) OVER (
      PARTITION BY account_name, transaction_year, CEIL(transaction_month::FLOAT / 3)
    ) AS quarterly_net_activity,
    
    SUM(net_activity) OVER (
      PARTITION BY account_name, transaction_year
      ORDER BY transaction_month
    ) AS ytd_net_activity,
    
    -- Flag accounts needing attention
    CASE 
      WHEN account_health_score < 40 THEN TRUE
      WHEN is_liability AND mom_balance_change_percent > 0.10 THEN TRUE
      WHEN NOT is_liability AND end_of_month_balance < 100 AND account_type != 'Home Loan' THEN TRUE
      ELSE FALSE
    END AS needs_attention_flag,
    
    -- Suggested actions
    CASE 
      WHEN is_mortgage AND mom_balance_change > 0 THEN 'Consider extra payments to reduce mortgage'
      WHEN is_liability AND mom_balance_change > 0 THEN 'Focus on paying down this debt'
      WHEN NOT is_liability AND end_of_month_balance < 500 AND account_type != 'Home Loan' THEN 'Consider building emergency fund'
      WHEN account_health_score > 80 THEN 'Account performing well'
      ELSE 'Monitor account performance'
    END AS suggested_action
    
  FROM account_performance_metrics
)

SELECT * FROM final_insights
ORDER BY transaction_year DESC, transaction_month DESC, account_health_score ASC
