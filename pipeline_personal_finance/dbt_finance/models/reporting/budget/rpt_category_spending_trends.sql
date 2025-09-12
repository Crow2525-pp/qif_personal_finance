{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['budget_year_month', 'category_level_1'], 'unique': false},
      {'columns': ['category_level_1'], 'unique': false}
    ]
  )
}}

WITH category_monthly_spending AS (
  SELECT 
    ft.transaction_year,
    ft.transaction_month,
    ft.transaction_year || '-' || LPAD(ft.transaction_month::TEXT, 2, '0') AS budget_year_month,
    dc.level_1_category,
    dc.level_2_subcategory,
    dc.level_3_store,
    dc.category_type,
    ft.is_internal_transfer,
    
    -- Expense amounts (only negative transactions, exclude internal transfers and income)
    SUM(CASE 
      WHEN ft.transaction_amount < 0 
       AND NOT ft.is_internal_transfer 
       AND NOT ft.is_income_transaction 
      THEN ABS(ft.transaction_amount) 
      ELSE 0 
    END) AS monthly_spending,
    
    COUNT(CASE 
      WHEN ft.transaction_amount < 0 
       AND NOT ft.is_internal_transfer 
       AND NOT ft.is_income_transaction 
      THEN 1 
    END) AS transaction_count,
    
    AVG(CASE 
      WHEN ft.transaction_amount < 0 
       AND NOT ft.is_internal_transfer 
       AND NOT ft.is_income_transaction 
      THEN ABS(ft.transaction_amount) 
    END) AS avg_transaction_amount,
    
    MAX(CASE 
      WHEN ft.transaction_amount < 0 
       AND NOT ft.is_internal_transfer 
       AND NOT ft.is_income_transaction 
      THEN ABS(ft.transaction_amount) 
    END) AS max_transaction_amount
    
  FROM {{ ref('fct_transactions_enhanced') }} ft
  LEFT JOIN {{ ref('dim_categories_enhanced') }} dc
    ON ft.category_key = dc.category_key
  WHERE NOT COALESCE(ft.is_internal_transfer, FALSE)
    AND NOT COALESCE(ft.is_income_transaction, FALSE)
  GROUP BY 
    ft.transaction_year, 
    ft.transaction_month,
    dc.level_1_category,
    dc.level_2_subcategory, 
    dc.level_3_store,
    dc.category_type,
    ft.is_internal_transfer
),

category_trends AS (
  SELECT 
    *,
    -- Month-over-month comparisons
    LAG(monthly_spending) OVER (
      PARTITION BY level_1_category, level_2_subcategory 
      ORDER BY transaction_year, transaction_month
    ) AS prev_month_spending,
    
    -- Calculate month-over-month change
    monthly_spending - LAG(monthly_spending) OVER (
      PARTITION BY level_1_category, level_2_subcategory 
      ORDER BY transaction_year, transaction_month
    ) AS mom_spending_change,
    
    -- Calculate percentage change
    CASE 
      WHEN LAG(monthly_spending) OVER (
        PARTITION BY level_1_category, level_2_subcategory 
        ORDER BY transaction_year, transaction_month
      ) > 0 
      THEN ((monthly_spending - LAG(monthly_spending) OVER (
        PARTITION BY level_1_category, level_2_subcategory 
        ORDER BY transaction_year, transaction_month
      )) / LAG(monthly_spending) OVER (
        PARTITION BY level_1_category, level_2_subcategory 
        ORDER BY transaction_year, transaction_month
      )) * 100
      ELSE NULL
    END AS mom_spending_change_percent,
    
    -- Rolling averages (3 months)
    AVG(monthly_spending) OVER (
      PARTITION BY level_1_category, level_2_subcategory 
      ORDER BY transaction_year, transaction_month
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3m_avg_spending,
    
    -- Year-over-year comparison
    LAG(monthly_spending, 12) OVER (
      PARTITION BY level_1_category, level_2_subcategory, transaction_month
      ORDER BY transaction_year
    ) AS yoy_same_month_spending,
    
    -- Percentage of total monthly spending
    monthly_spending / SUM(monthly_spending) OVER (
      PARTITION BY transaction_year, transaction_month
    ) * 100 AS percent_of_total_monthly_spending
    
  FROM category_monthly_spending
),

category_summary_stats AS (
  SELECT 
    level_1_category,
    level_2_subcategory,
    
    -- Overall statistics
    COUNT(*) AS total_months_with_spending,
    SUM(monthly_spending) AS total_spending_all_time,
    AVG(monthly_spending) AS avg_monthly_spending,
    STDDEV(monthly_spending) AS stddev_monthly_spending,
    MIN(monthly_spending) AS min_monthly_spending,
    MAX(monthly_spending) AS max_monthly_spending,
    
    -- Recent trends (last 3 months)
    AVG(CASE 
      WHEN (transaction_year || '-' || LPAD(transaction_month::TEXT, 2, '0') || '-01')::DATE >= (
        SELECT (MAX(transaction_year) || '-' || LPAD(MAX(transaction_month)::TEXT, 2, '0') || '-01')::DATE - INTERVAL '2 months'
        FROM category_trends ct2 
        WHERE ct2.level_1_category = category_trends.level_1_category
          AND ct2.level_2_subcategory = category_trends.level_2_subcategory
      )
      THEN monthly_spending 
    END) AS avg_spending_last_3m,
    
    -- Volatility indicator
    CASE 
      WHEN AVG(monthly_spending) > 0 
      THEN (STDDEV(monthly_spending) / AVG(monthly_spending)) * 100
      ELSE 0
    END AS spending_volatility_coefficient
    
  FROM category_trends
  GROUP BY level_1_category, level_2_subcategory
),

final_report AS (
  SELECT 
    ct.*,
    
    -- Add summary statistics
    cs.total_spending_all_time,
    cs.avg_monthly_spending AS category_avg_monthly_spending,
    cs.spending_volatility_coefficient,
    cs.avg_spending_last_3m,
    
    -- Spending trend classification
    CASE 
      WHEN mom_spending_change_percent > 20 THEN 'Increasing Significantly'
      WHEN mom_spending_change_percent > 5 THEN 'Increasing'
      WHEN mom_spending_change_percent > -5 THEN 'Stable'
      WHEN mom_spending_change_percent > -20 THEN 'Decreasing'
      ELSE 'Decreasing Significantly'
    END AS spending_trend_category,
    
    -- Budget planning insights
    CASE 
      WHEN cs.spending_volatility_coefficient > 50 THEN 'High Variability - Plan Buffer'
      WHEN cs.spending_volatility_coefficient > 25 THEN 'Moderate Variability'
      ELSE 'Stable Spending Pattern'
    END AS budget_planning_insight,
    
    -- Rank categories by spending within each month
    RANK() OVER (
      PARTITION BY budget_year_month 
      ORDER BY monthly_spending DESC
    ) AS monthly_spending_rank,
    
    CURRENT_TIMESTAMP AS report_generated_at
    
  FROM category_trends ct
  LEFT JOIN category_summary_stats cs
    ON ct.level_1_category = cs.level_1_category
    AND ct.level_2_subcategory = cs.level_2_subcategory
)

SELECT * FROM final_report
WHERE monthly_spending > 0 -- Only include months with actual spending
ORDER BY transaction_year DESC, transaction_month DESC, monthly_spending DESC