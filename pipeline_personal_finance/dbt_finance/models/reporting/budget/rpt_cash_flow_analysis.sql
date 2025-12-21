{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['budget_year_month'], 'unique': true},
      {'columns': ['transaction_year'], 'unique': false}
    ]
  )
}}

WITH cash_flow_base AS (
  SELECT 
    ft.transaction_year,
    ft.transaction_month,
    ft.transaction_year || '-' || LPAD(ft.transaction_month::TEXT, 2, '0') AS budget_year_month,
    ft.transaction_date,
    ft.transaction_amount,
    
    da.account_name,
    da.account_type,
    da.account_category,
    da.is_liability,
    da.is_transactional,
    
    ft.is_income_transaction,
    ft.is_internal_transfer,
    dc.level_1_category,
    dc.category_type,
    
    -- Classify cash flow direction
    CASE 
      WHEN ft.is_internal_transfer THEN 'Internal Transfer'
      WHEN ft.is_income_transaction THEN 'Cash Inflow'
      WHEN ft.transaction_amount < 0 THEN 'Cash Outflow'
      WHEN ft.transaction_amount > 0 AND NOT ft.is_income_transaction THEN 'Other Inflow'
      ELSE 'Neutral'
    END AS cash_flow_type,
    
    -- Categorize by operational vs financing vs investing
    CASE 
      WHEN ft.is_internal_transfer THEN 'Financing'
      WHEN dc.level_1_category IN ('Salary', 'Food & Drink', 'Household & Services', 'Family & Kids') THEN 'Operating'
      WHEN dc.level_1_category IN ('Mortgage') THEN 'Financing'
      WHEN dc.level_1_category LIKE '%Investment%' OR da.account_name LIKE '%invest%' THEN 'Investing'
      ELSE 'Operating'
    END AS cash_flow_category
    
  FROM {{ ref('fct_transactions_enhanced') }} ft
  LEFT JOIN {{ ref('dim_accounts_enhanced') }} da
    ON ft.account_key = da.account_key
  LEFT JOIN {{ ref('dim_categories_enhanced') }} dc
    ON ft.category_key = dc.category_key
),

monthly_cash_flow AS (
  SELECT 
    budget_year_month,
    transaction_year,
    transaction_month,
    
    -- Total cash flows (excluding internal transfers)
    SUM(CASE 
      WHEN cash_flow_type = 'Cash Inflow' THEN ABS(transaction_amount)
      ELSE 0 
    END) AS total_inflows,
    
    SUM(CASE 
      WHEN cash_flow_type = 'Cash Outflow' THEN ABS(transaction_amount)
      ELSE 0 
    END) AS total_outflows,
    
    SUM(CASE 
      WHEN cash_flow_type = 'Internal Transfer' THEN ABS(transaction_amount)
      ELSE 0 
    END) AS total_internal_transfers,
    
    -- Net cash flow
    SUM(CASE 
      WHEN cash_flow_type = 'Cash Inflow' THEN ABS(transaction_amount)
      WHEN cash_flow_type = 'Cash Outflow' THEN -ABS(transaction_amount)
      ELSE 0 
    END) AS net_cash_flow,
    
    -- By category
    SUM(CASE 
      WHEN cash_flow_category = 'Operating' AND cash_flow_type = 'Cash Inflow' 
      THEN ABS(transaction_amount) ELSE 0 
    END) AS operating_inflows,
    
    SUM(CASE 
      WHEN cash_flow_category = 'Operating' AND cash_flow_type = 'Cash Outflow' 
      THEN ABS(transaction_amount) ELSE 0 
    END) AS operating_outflows,
    
    SUM(CASE 
      WHEN cash_flow_category = 'Financing' AND cash_flow_type != 'Internal Transfer'
      THEN CASE WHEN transaction_amount < 0 THEN -ABS(transaction_amount) ELSE ABS(transaction_amount) END
      ELSE 0 
    END) AS financing_cash_flow,
    
    SUM(CASE 
      WHEN cash_flow_category = 'Investing' AND cash_flow_type != 'Internal Transfer'
      THEN CASE WHEN transaction_amount < 0 THEN -ABS(transaction_amount) ELSE ABS(transaction_amount) END
      ELSE 0 
    END) AS investing_cash_flow,
    
    -- Transaction counts
    COUNT(CASE WHEN cash_flow_type = 'Cash Inflow' THEN 1 END) AS inflow_transaction_count,
    COUNT(CASE WHEN cash_flow_type = 'Cash Outflow' THEN 1 END) AS outflow_transaction_count,
    COUNT(CASE WHEN cash_flow_type = 'Internal Transfer' THEN 1 END) AS internal_transfer_count,
    
    -- Average transaction sizes
    AVG(CASE WHEN cash_flow_type = 'Cash Inflow' THEN ABS(transaction_amount) END) AS avg_inflow_amount,
    AVG(CASE WHEN cash_flow_type = 'Cash Outflow' THEN ABS(transaction_amount) END) AS avg_outflow_amount
    
  FROM cash_flow_base
  GROUP BY budget_year_month, transaction_year, transaction_month
),

cash_flow_trends AS (
  SELECT 
    *,
    -- Operating cash flow (core business of household)
    operating_inflows - operating_outflows AS operating_cash_flow,
    
    -- Cash flow ratios and metrics
    CASE WHEN total_inflows > 0 THEN (total_outflows / total_inflows) ELSE 0 END AS outflow_to_inflow_ratio,
    CASE WHEN total_inflows > 0 THEN (net_cash_flow / total_inflows) ELSE 0 END AS cash_flow_margin_percent,
    
    -- Month-over-month changes
    LAG(total_inflows) OVER (ORDER BY transaction_year, transaction_month) AS prev_month_inflows,
    LAG(total_outflows) OVER (ORDER BY transaction_year, transaction_month) AS prev_month_outflows,
    LAG(net_cash_flow) OVER (ORDER BY transaction_year, transaction_month) AS prev_month_net_flow,
    
    -- Rolling averages (3 months)
    AVG(total_inflows) OVER (
      ORDER BY transaction_year, transaction_month
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3m_avg_inflows,
    
    AVG(total_outflows) OVER (
      ORDER BY transaction_year, transaction_month
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW  
    ) AS rolling_3m_avg_outflows,
    
    AVG(net_cash_flow) OVER (
      ORDER BY transaction_year, transaction_month
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3m_avg_net_flow,
    
    -- Cumulative year-to-date flows
    SUM(total_inflows) OVER (
      PARTITION BY transaction_year 
      ORDER BY transaction_month
    ) AS ytd_inflows,
    
    SUM(total_outflows) OVER (
      PARTITION BY transaction_year
      ORDER BY transaction_month
    ) AS ytd_outflows,
    
    SUM(net_cash_flow) OVER (
      PARTITION BY transaction_year
      ORDER BY transaction_month
    ) AS ytd_net_cash_flow
    
  FROM monthly_cash_flow
),

cash_flow_analysis AS (
  SELECT 
    *,
    -- Calculate month-over-month percentage changes
    CASE 
      WHEN prev_month_inflows > 0 
      THEN ((total_inflows - prev_month_inflows) / prev_month_inflows)
      ELSE NULL 
    END AS mom_inflow_change_percent,
    
    CASE 
      WHEN prev_month_outflows > 0 
      THEN ((total_outflows - prev_month_outflows) / prev_month_outflows)
      ELSE NULL 
    END AS mom_outflow_change_percent,
    
    -- Cash flow health indicators
    CASE 
      WHEN net_cash_flow > 0 THEN 'Positive'
      WHEN net_cash_flow = 0 THEN 'Breakeven' 
      ELSE 'Negative'
    END AS cash_flow_status,
    
    -- Cash flow stability (based on variability)
    ABS(net_cash_flow - rolling_3m_avg_net_flow) AS cash_flow_variance_from_trend,
    
    -- Cash flow trend classification
    CASE 
      WHEN net_cash_flow > rolling_3m_avg_net_flow * 1.1 THEN 'Improving'
      WHEN net_cash_flow < rolling_3m_avg_net_flow * 0.9 THEN 'Declining' 
      ELSE 'Stable'
    END AS cash_flow_trend,
    
    -- Seasonal patterns (by month)
    AVG(net_cash_flow) OVER (
      PARTITION BY transaction_month
    ) AS seasonal_avg_net_flow,
    
    -- Cash flow efficiency score (1-100)
    LEAST(100, GREATEST(0,
      50 + -- Base score
      (CASE WHEN net_cash_flow > 0 THEN 30 ELSE -20 END) + -- Positive cash flow bonus
      (CASE WHEN cash_flow_margin_percent > 0.10 THEN 20 ELSE 0 END) + -- High margin bonus
      (CASE WHEN outflow_to_inflow_ratio < 0.80 THEN 10 ELSE -10 END) -- Efficiency bonus/penalty
    )) AS cash_flow_efficiency_score,
    
    CURRENT_TIMESTAMP AS report_generated_at
    
  FROM cash_flow_trends
),

final_insights AS (
  SELECT 
    *,
    -- Ranked status (1 worst .. 5 best)
    CASE 
      WHEN cash_flow_status = 'Negative' AND cash_flow_trend = 'Declining' THEN 1
      WHEN cash_flow_status = 'Negative' THEN 2
      WHEN cash_flow_status = 'Breakeven' THEN 3
      WHEN cash_flow_status = 'Positive' AND cash_flow_trend <> 'Improving' THEN 4
      WHEN cash_flow_status = 'Positive' AND cash_flow_trend = 'Improving' THEN 5
      ELSE 3
    END AS cash_flow_status_rank,

    -- Percentile position among all months by efficiency
    PERCENT_RANK() OVER (ORDER BY cash_flow_efficiency_score) AS cash_flow_efficiency_percentile,

    -- Human-friendly compound status with rank
    (cash_flow_status || ' (' || cash_flow_trend || ') — Rank ' ||
      CASE 
        WHEN cash_flow_status = 'Negative' AND cash_flow_trend = 'Declining' THEN '1/5'
        WHEN cash_flow_status = 'Negative' THEN '2/5'
        WHEN cash_flow_status = 'Breakeven' THEN '3/5'
        WHEN cash_flow_status = 'Positive' AND cash_flow_trend <> 'Improving' THEN '4/5'
        WHEN cash_flow_status = 'Positive' AND cash_flow_trend = 'Improving' THEN '5/5'
        ELSE '3/5'
      END
    ) AS cash_flow_status_compound,
    -- Add actionable insights
    CASE 
      WHEN cash_flow_efficiency_score < 40 THEN 'Critical - Review spending immediately'
      WHEN net_cash_flow < 0 AND cash_flow_trend = 'Declining' THEN 'Warning - Negative cash flow trend'
      WHEN outflow_to_inflow_ratio > 0.95 THEN 'Caution - Very tight cash flow'
      WHEN net_cash_flow > rolling_3m_avg_net_flow * 1.5 THEN 'Excellent - Consider investment opportunities'
      WHEN cash_flow_efficiency_score > 80 THEN 'Good - Maintain current patterns'
      ELSE 'Monitor - Track trends closely'
    END AS cash_flow_recommendation,
    
    -- Forecast next month (simple trend-based)
    CASE 
      WHEN cash_flow_trend = 'Improving' THEN rolling_3m_avg_net_flow * 1.05
      WHEN cash_flow_trend = 'Declining' THEN rolling_3m_avg_net_flow * 0.95
      ELSE rolling_3m_avg_net_flow
    END AS forecasted_next_month_net_flow,
    
    -- Days of expenses covered (if we have positive net flow)
    CASE 
      WHEN total_outflows > 0 AND net_cash_flow > 0 
      THEN (net_cash_flow / (total_outflows / 30))
      ELSE NULL 
    END AS days_expenses_covered
    
  FROM cash_flow_analysis
)

SELECT * FROM final_insights
ORDER BY transaction_year DESC, transaction_month DESC
