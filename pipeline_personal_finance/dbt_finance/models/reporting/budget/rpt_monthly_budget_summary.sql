{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['budget_year_month'], 'unique': true},
      {'columns': ['budget_year'], 'unique': false}
    ]
  )
}}

WITH monthly_transactions AS (
  SELECT 
    ft.transaction_year,
    ft.transaction_month,
    ft.transaction_date,
    dc.category_type,
    dc.level_1_category,
    {{ metric_income('ft') }}  AS income_amount,
    {{ metric_expense(false, 'ft', 'dc') }} AS expense_amount
  FROM {{ ref('fct_transactions_enhanced') }} ft
  LEFT JOIN {{ ref('dim_categories_enhanced') }} dc
    ON ft.category_key = dc.category_key
),

monthly_aggregation AS (
  SELECT
    transaction_year AS budget_year,
    transaction_month AS budget_month,
    transaction_year || '-' || LPAD(transaction_month::TEXT, 2, '0') AS budget_year_month,
    DATE_TRUNC('month', MIN(transaction_date)) AS month_start_date,
    
    -- Income metrics
    SUM(income_amount) AS total_income,
    COUNT(CASE WHEN income_amount > 0 THEN 1 END) AS income_transaction_count,
    
    -- Expense metrics
    SUM(expense_amount) AS total_expenses,
    COUNT(CASE WHEN expense_amount > 0 THEN 1 END) AS expense_transaction_count,
    
    -- Net cash flow
    SUM(income_amount) - SUM(expense_amount) AS net_cash_flow,
    
    -- Category breakdowns
    SUM(CASE WHEN level_1_category = 'Mortgage' THEN expense_amount ELSE 0 END) AS mortgage_expenses,
    SUM(CASE WHEN level_1_category = 'Household & Services' THEN expense_amount ELSE 0 END) AS household_expenses,
    SUM(CASE WHEN level_1_category = 'Food & Drink' THEN expense_amount ELSE 0 END) AS food_expenses,
    SUM(CASE WHEN level_1_category = 'Family & Kids' THEN expense_amount ELSE 0 END) AS family_expenses,
    
    -- Total transaction volume
    COUNT(*) AS total_transactions,
    SUM(income_amount + expense_amount) AS total_transaction_volume
    
  FROM monthly_transactions
  GROUP BY transaction_year, transaction_month
),

final_metrics AS (
  SELECT 
    *,
    -- Calculated metrics (ratios, not percent-scaled)
    CASE WHEN total_income > 0 THEN (net_cash_flow / total_income) ELSE 0 END AS savings_rate_percent,
    CASE WHEN total_income > 0 THEN (total_expenses / total_income) ELSE 0 END AS expense_ratio_percent,
    total_expenses / NULLIF(expense_transaction_count, 0) AS avg_expense_amount,
    
    -- Period comparisons
    LAG(total_income) OVER (ORDER BY budget_year, budget_month) AS prev_month_income,
    LAG(total_expenses) OVER (ORDER BY budget_year, budget_month) AS prev_month_expenses,
    LAG(net_cash_flow) OVER (ORDER BY budget_year, budget_month) AS prev_month_net_flow,
    
    -- Rolling averages (3 month)
    AVG(total_income) OVER (
      ORDER BY budget_year, budget_month 
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3m_avg_income,
    AVG(total_expenses) OVER (
      ORDER BY budget_year, budget_month 
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW  
    ) AS rolling_3m_avg_expenses,
    
    -- Year-to-date running totals
    SUM(total_income) OVER (
      PARTITION BY budget_year 
      ORDER BY budget_month
    ) AS ytd_income,
    SUM(total_expenses) OVER (
      PARTITION BY budget_year
      ORDER BY budget_month  
    ) AS ytd_expenses,
    SUM(net_cash_flow) OVER (
      PARTITION BY budget_year
      ORDER BY budget_month
    ) AS ytd_net_cash_flow,
    
    -- Metadata
    CURRENT_TIMESTAMP AS report_generated_at
    
  FROM monthly_aggregation
)

SELECT * FROM final_metrics
ORDER BY budget_year DESC, budget_month DESC
