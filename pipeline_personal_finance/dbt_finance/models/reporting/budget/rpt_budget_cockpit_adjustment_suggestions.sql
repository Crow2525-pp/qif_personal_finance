{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['analysis_month'], 'unique': false}
    ]
  )
}}

WITH monthly_category_spending AS (
  SELECT
    ft.transaction_year,
    ft.transaction_month,
    ft.transaction_year || '-' || LPAD(ft.transaction_month::TEXT, 2, '0') as budget_year_month,
    dc.level_1_category,
    dc.level_2_subcategory,
    SUM(CASE WHEN ft.transaction_amount < 0 THEN ABS(ft.transaction_amount) ELSE 0 END) as category_spending
  FROM {{ ref('fct_transactions') }} ft
  INNER JOIN {{ ref('dim_categories') }} dc ON ft.category_key = dc.category_key
  WHERE dc.is_internal_transfer = false
    AND dc.category_type = 'Expense'
  GROUP BY ft.transaction_year, ft.transaction_month, budget_year_month, dc.level_1_category, dc.level_2_subcategory
),

category_historical_avg AS (
  SELECT
    level_1_category,
    AVG(category_spending) as avg_spending,
    STDDEV(category_spending) as stddev_spending,
    COUNT(*) as month_count
  FROM monthly_category_spending
  WHERE budget_year_month < TO_CHAR(CURRENT_DATE, 'YYYY-MM')
  GROUP BY level_1_category
),

recent_months_analysis AS (
  SELECT
    mcs.level_1_category,
    mcs.level_2_subcategory,
    mcs.category_spending,
    mcs.budget_year_month,
    cha.avg_spending,
    cha.stddev_spending,
    ROW_NUMBER() OVER (PARTITION BY mcs.level_1_category ORDER BY mcs.budget_year_month DESC) as month_rank,
    -- Calculate variance
    ROUND((mcs.category_spending - cha.avg_spending) / NULLIF(cha.avg_spending, 0) * 100, 1) as pct_variance_from_avg,
    -- Standard deviation check (>1 stdev above)
    CASE
      WHEN mcs.category_spending > (cha.avg_spending + cha.stddev_spending) THEN TRUE
      ELSE FALSE
    END as is_outlier,
    -- Overspend amount
    ROUND(GREATEST(0, mcs.category_spending - cha.avg_spending), 2) as overspend_amount
  FROM monthly_category_spending mcs
  INNER JOIN category_historical_avg cha ON mcs.level_1_category = cha.level_1_category
  WHERE mcs.budget_year_month < TO_CHAR(CURRENT_DATE, 'YYYY-MM')
),

overspending_categories AS (
  SELECT
    level_1_category,
    level_2_subcategory,
    budget_year_month,
    category_spending,
    avg_spending,
    pct_variance_from_avg,
    is_outlier,
    overspend_amount,
    month_rank,
    -- Count consecutive months of overspending
    SUM(CASE WHEN overspend_amount <= 0 THEN 1 ELSE 0 END) OVER (
      PARTITION BY level_1_category
      ORDER BY budget_year_month DESC
    ) as consecutive_overspend_group
  FROM recent_months_analysis
  WHERE month_rank <= 3
),

consecutive_overspending AS (
  SELECT
    level_1_category,
    level_2_subcategory,
    MIN(budget_year_month) as first_overspend_month,
    MAX(budget_year_month) as most_recent_month,
    COUNT(*) as months_of_consecutive_overspend,
    ROUND(SUM(overspend_amount), 2) as total_cumulative_overspend,
    ROUND(AVG(category_spending), 2) as avg_recent_spending,
    ROUND(AVG(avg_spending), 2) as historical_avg,
    ROUND(COUNT(*) * (MAX(category_spending) - MAX(avg_spending)), 2) as projected_annual_impact
  FROM overspending_categories
  WHERE overspend_amount > 0
  GROUP BY level_1_category, level_2_subcategory, consecutive_overspend_group
  HAVING COUNT(*) >= 2  -- Only consider 2+ consecutive months
),

next_month AS (
  SELECT DATE_TRUNC('month', CURRENT_DATE + INTERVAL '1 month') as month_start
),

adjustment_recommendations AS (
  SELECT
    nm.month_start as adjustment_month,
    TO_CHAR(nm.month_start, 'YYYY-MM') as adjustment_month_formatted,
    ROW_NUMBER() OVER (ORDER BY co.total_cumulative_overspend DESC) as adjustment_rank,
    co.level_1_category,
    co.level_2_subcategory,
    co.months_of_consecutive_overspend,
    ROUND(co.avg_recent_spending, 2) as suggested_budget_amount,
    ROUND(co.historical_avg, 2) as historical_average,
    ROUND(co.avg_recent_spending - co.historical_avg, 2) as required_reduction,
    ROUND(((co.avg_recent_spending - co.historical_avg) / NULLIF(co.historical_avg, 0)) * 100, 1) as reduction_pct,
    ROUND(co.total_cumulative_overspend, 2) as total_overspend,
    ROUND(co.projected_annual_impact, 2) as projected_annual_impact,
    -- Adjustment rationale
    CASE
      WHEN co.months_of_consecutive_overspend >= 3 THEN
        'Critical: ' || co.months_of_consecutive_overspend || ' consecutive months over budget'
      WHEN co.total_cumulative_overspend > 500 THEN
        'Significant: $' || ROUND(co.total_cumulative_overspend, 0)::TEXT || ' cumulative overspend'
      ELSE
        'Moderate: Consider budget adjustment for ' || co.level_1_category
    END as adjustment_rationale,
    -- Priority score
    CASE
      WHEN co.months_of_consecutive_overspend >= 3 AND co.total_cumulative_overspend > 500 THEN 1
      WHEN co.months_of_consecutive_overspend >= 2 AND co.total_cumulative_overspend > 250 THEN 2
      WHEN co.total_cumulative_overspend > 100 THEN 3
      ELSE 4
    END as priority,
    CURRENT_TIMESTAMP as report_generated_at
  FROM consecutive_overspending co
  CROSS JOIN next_month nm
)

SELECT * FROM adjustment_recommendations
ORDER BY adjustment_month DESC, priority ASC, total_overspend DESC
LIMIT 5  -- Show top 5 recommendations
