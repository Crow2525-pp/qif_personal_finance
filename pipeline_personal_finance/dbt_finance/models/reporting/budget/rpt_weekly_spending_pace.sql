{{
  config(
    materialized='table'
  )
}}

/*
  Week-to-Date Spending Pace Analysis
  Shows current week spending vs weekly budget target.
  Helps answer: "Are we on track this week?"

  Note: Uses ISODOW (1=Monday, 7=Sunday) to match DATE_TRUNC('week') which starts on Monday
*/

WITH latest_available_month AS (
  -- Get the most recent month with data (fallback if current month doesn't exist)
  SELECT MAX(budget_year_month) AS latest_month
  FROM {{ ref('rpt_monthly_budget_summary') }}
),

current_month_budget AS (
  -- Get the rolling 3-month average as the monthly budget target
  -- Use current month if available, otherwise use the latest available month
  SELECT
    rolling_3m_avg_expenses AS monthly_budget_target,
    total_expenses AS current_month_expenses
  FROM {{ ref('rpt_monthly_budget_summary') }}
  WHERE budget_year_month = COALESCE(
    (SELECT budget_year_month FROM {{ ref('rpt_monthly_budget_summary') }} WHERE budget_year_month = TO_CHAR(CURRENT_DATE, 'YYYY-MM')),
    (SELECT latest_month FROM latest_available_month)
  )
),

month_context AS (
  SELECT
    DATE_TRUNC('month', CURRENT_DATE) AS month_start,
    (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month' - INTERVAL '1 day')::DATE AS month_end,
    DATE_TRUNC('week', CURRENT_DATE) AS week_start,
    (DATE_TRUNC('week', CURRENT_DATE) + INTERVAL '6 days')::DATE AS week_end,
    EXTRACT(DAY FROM CURRENT_DATE)::INT AS current_day_of_month,
    EXTRACT(ISODOW FROM CURRENT_DATE)::INT AS current_day_of_week,  -- 1=Monday, 7=Sunday
    EXTRACT(DAY FROM (DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month' - INTERVAL '1 day'))::INT AS days_in_month
),

weekly_target AS (
  SELECT
    mc.*,
    cmb.monthly_budget_target,
    cmb.current_month_expenses,
    -- Calculate weeks in month (approximate)
    CEIL(mc.days_in_month / 7.0) AS weeks_in_month,
    -- Weekly budget = monthly budget / 4.33 (average weeks per month)
    ROUND((cmb.monthly_budget_target / 4.33)::numeric, 2) AS weekly_budget_target,
    -- Daily budget
    ROUND((cmb.monthly_budget_target / mc.days_in_month)::numeric, 2) AS daily_budget_target
  FROM month_context mc
  CROSS JOIN current_month_budget cmb
),

week_transactions AS (
  SELECT
    SUM({{ metric_expense(false, 'ft', 'dc') }}) AS wtd_spending
  FROM {{ ref('fct_transactions') }} ft
  LEFT JOIN {{ ref('dim_categories') }} dc ON ft.category_key = dc.category_key
  WHERE ft.transaction_date >= (SELECT week_start FROM month_context)
    AND ft.transaction_date <= CURRENT_DATE
),

mtd_transactions AS (
  SELECT
    SUM({{ metric_expense(false, 'ft', 'dc') }}) AS mtd_spending
  FROM {{ ref('fct_transactions') }} ft
  LEFT JOIN {{ ref('dim_categories') }} dc ON ft.category_key = dc.category_key
  WHERE ft.transaction_date >= (SELECT month_start FROM month_context)
    AND ft.transaction_date <= CURRENT_DATE
)

SELECT
  wt.week_start,
  wt.week_end,
  wt.month_start,
  wt.current_day_of_month,
  wt.current_day_of_week AS day_of_week,  -- 1=Monday, 2=Tuesday, ..., 7=Sunday
  wt.days_in_month,
  wt.days_in_month - wt.current_day_of_month AS days_remaining_in_month,
  7 - wt.current_day_of_week AS days_remaining_in_week,

  -- Budget targets
  wt.monthly_budget_target,
  wt.weekly_budget_target,
  wt.daily_budget_target,

  -- Actual spending
  COALESCE(wtx.wtd_spending, 0) AS wtd_spending,
  COALESCE(mtx.mtd_spending, 0) AS mtd_spending,

  -- Week-to-date pacing
  ROUND((wt.daily_budget_target * wt.current_day_of_week)::numeric, 2) AS wtd_budget_target,
  ROUND((wt.daily_budget_target * wt.current_day_of_week)::numeric, 2) AS expected_spend_to_date,
  COALESCE(wtx.wtd_spending, 0) - ROUND((wt.daily_budget_target * wt.current_day_of_week)::numeric, 2) AS wtd_variance,

  -- Pace ratio (percentage)
  ROUND((COALESCE(wtx.wtd_spending, 0) / NULLIF(ROUND((wt.daily_budget_target * wt.current_day_of_week)::numeric, 2), 0) * 100)::numeric, 1) AS pace_ratio,

  -- Daily budget remaining for rest of week
  CASE
    WHEN (7 - wt.current_day_of_week) > 0
    THEN ROUND(((wt.weekly_budget_target - COALESCE(wtx.wtd_spending, 0)) / (7 - wt.current_day_of_week))::numeric, 2)
    ELSE 0
  END AS daily_budget_remaining,

  -- Pace status
  CASE
    WHEN COALESCE(wtx.wtd_spending, 0) <= (wt.daily_budget_target * wt.current_day_of_week * 0.9) THEN 'Under Budget'
    WHEN COALESCE(wtx.wtd_spending, 0) <= (wt.daily_budget_target * wt.current_day_of_week * 1.1) THEN 'On Track'
    ELSE 'Over Budget'
  END AS pace_status,

  -- Month-to-date pacing
  ROUND((wt.daily_budget_target * wt.current_day_of_month)::numeric, 2) AS mtd_budget_target,
  COALESCE(mtx.mtd_spending, 0) - ROUND((wt.daily_budget_target * wt.current_day_of_month)::numeric, 2) AS mtd_variance,

  -- Projected month end
  CASE
    WHEN wt.current_day_of_month > 0
    THEN ROUND(((COALESCE(mtx.mtd_spending, 0) / wt.current_day_of_month) * wt.days_in_month)::numeric, 2)
    ELSE 0
  END AS projected_month_end_spending,

  CURRENT_TIMESTAMP AS report_generated_at

FROM weekly_target wt
CROSS JOIN week_transactions wtx
CROSS JOIN mtd_transactions mtx
