{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['tracking_date'], 'unique': false}
    ]
  )
}}

WITH current_month AS (
  SELECT
    DATE_TRUNC('month', CURRENT_DATE) as month_start,
    CURRENT_DATE as today,
    EXTRACT(DAY FROM DATE_TRUNC('month', CURRENT_DATE + INTERVAL '1 month') - INTERVAL '1 day') as days_in_month,
    EXTRACT(DAY FROM CURRENT_DATE) as current_day_of_month
),

month_transactions AS (
  SELECT
    ft.transaction_date,
    ft.transaction_amount,
    CASE WHEN ft.transaction_amount > 0 THEN ft.transaction_amount ELSE 0 END as income_amount,
    CASE WHEN ft.transaction_amount < 0 THEN ABS(ft.transaction_amount) ELSE 0 END as expense_amount
  FROM {{ ref('fct_transactions') }} ft
  CROSS JOIN current_month cm
  WHERE DATE_TRUNC('month', ft.transaction_date) = cm.month_start
    AND ft.category_key NOT IN (
      SELECT category_key FROM {{ ref('dim_categories') }} WHERE is_internal_transfer = true
    )
),

month_totals AS (
  SELECT
    SUM(income_amount) as mtd_income,
    SUM(expense_amount) as mtd_expenses,
    COUNT(DISTINCT CASE WHEN expense_amount > 0 THEN transaction_date END) as days_with_spending
  FROM month_transactions
),

daily_targets AS (
  SELECT
    cm.*,
    mt.mtd_income,
    mt.mtd_expenses,
    mt.days_with_spending,
    -- Calculate daily targets based on full-month historical average
    (SELECT AVG(daily_expenses) FROM (
      SELECT
        DATE_TRUNC('month', ft.transaction_date) as month,
        EXTRACT(DAY FROM DATE_TRUNC('month', ft.transaction_date + INTERVAL '1 month') - INTERVAL '1 day') as days_in_m,
        SUM(CASE WHEN ft.transaction_amount < 0 THEN ABS(ft.transaction_amount) ELSE 0 END) /
        EXTRACT(DAY FROM DATE_TRUNC('month', ft.transaction_date + INTERVAL '1 month') - INTERVAL '1 day') as daily_expenses
      FROM {{ ref('fct_transactions') }} ft
      WHERE ft.transaction_date >= CURRENT_DATE - INTERVAL '6 months'
        AND ft.transaction_date < DATE_TRUNC('month', CURRENT_DATE)
        AND ft.category_key NOT IN (
          SELECT category_key FROM {{ ref('dim_categories') }} WHERE is_internal_transfer = true
        )
      GROUP BY month, days_in_m
    ) daily_calcs) as avg_daily_expense_target
  FROM current_month cm
  CROSS JOIN month_totals mt
),

pace_analysis AS (
  SELECT
    dt.month_start,
    dt.today,
    dt.current_day_of_month,
    dt.days_in_month,
    dt.mtd_income,
    dt.mtd_expenses,
    dt.days_with_spending,
    ROUND(dt.avg_daily_expense_target, 2) as daily_expense_target,
    -- Pace calculations
    ROUND(dt.mtd_expenses / NULLIF(dt.current_day_of_month, 0), 2) as actual_daily_burn_rate,
    ROUND(dt.mtd_expenses / NULLIF(dt.avg_daily_expense_target, 0), 2) as pace_vs_target_ratio,
    -- Projected month-end
    ROUND(dt.mtd_expenses * (dt.days_in_month::FLOAT / dt.current_day_of_month), 2) as projected_month_end_expenses,
    -- Days remaining
    dt.days_in_month - dt.current_day_of_month as days_remaining,
    -- Variance from target
    ROUND(dt.mtd_expenses - (dt.avg_daily_expense_target * dt.current_day_of_month), 2) as mtd_variance_from_target,
    -- Rate comparison
    CASE
      WHEN dt.mtd_expenses / NULLIF(dt.current_day_of_month, 0) > dt.avg_daily_expense_target THEN 'Above pace'
      WHEN dt.mtd_expenses / NULLIF(dt.current_day_of_month, 0) < dt.avg_daily_expense_target * 0.9 THEN 'Below pace'
      ELSE 'On pace'
    END as pace_status,
    -- Health flag
    CASE
      WHEN (dt.mtd_expenses / NULLIF(dt.current_day_of_month, 0)) > (dt.avg_daily_expense_target * 1.25) THEN 'critical'
      WHEN (dt.mtd_expenses / NULLIF(dt.current_day_of_month, 0)) > (dt.avg_daily_expense_target * 1.1) THEN 'warning'
      ELSE 'healthy'
    END as pace_health,
    CURRENT_TIMESTAMP as report_generated_at
  FROM daily_targets dt
)

SELECT * FROM pace_analysis
