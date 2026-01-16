{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['budget_year_month'], 'unique': false},
      {'columns': ['adjustment_priority'], 'unique': false}
    ]
  )
}}

WITH latest_month_variance AS (
  SELECT
    budget_year_month,
    transaction_year,
    transaction_month,

    -- Get the most recent complete month
    ROW_NUMBER() OVER (ORDER BY transaction_year DESC, transaction_month DESC) AS recency_rank,

    mortgage_variance_pct,
    mortgage_variance_delta,
    mortgage_expenses,
    target_mortgage,

    household_variance_pct,
    household_variance_delta,
    household_expenses,
    target_household,

    food_variance_pct,
    food_variance_delta,
    food_expenses,
    target_food,

    family_variance_pct,
    family_variance_delta,
    family_expenses,
    target_family,

    net_cash_flow,
    savings_rate_percent,
    total_expenses,
    target_expenses

  FROM {{ ref('rpt_budget_variance_summary') }}
),

variance_ranked AS (
  SELECT
    budget_year_month,
    transaction_year,
    transaction_month,

    -- Identify categories to adjust
    CASE
      WHEN mortgage_variance_pct > 10 THEN ARRAY[('Mortgage', mortgage_expenses, target_mortgage, mortgage_variance_pct, mortgage_variance_delta)]
      ELSE ARRAY[]::record[]
    END ||
    CASE
      WHEN household_variance_pct > 10 THEN ARRAY[('Household & Services', household_expenses, target_household, household_variance_pct, household_variance_delta)]
      ELSE ARRAY[]::record[]
    END ||
    CASE
      WHEN food_variance_pct > 10 THEN ARRAY[('Food & Drink', food_expenses, target_food, food_variance_pct, food_variance_delta)]
      ELSE ARRAY[]::record[]
    END ||
    CASE
      WHEN family_variance_pct > 10 THEN ARRAY[('Family & Kids', family_expenses, target_family, family_variance_pct, family_variance_delta)]
      ELSE ARRAY[]::record[]
    END AS categories_to_reduce,

    net_cash_flow,
    savings_rate_percent,
    total_expenses,
    target_expenses

  FROM latest_month_variance
  WHERE recency_rank = 1
),

suggestions_base AS (
  SELECT
    budget_year_month,
    transaction_year,
    transaction_month,
    net_cash_flow,
    savings_rate_percent,
    total_expenses,
    target_expenses,
    categories_to_reduce

  FROM variance_ranked
),

-- Unnest and prioritize suggestions
suggestions_unpacked AS (
  SELECT
    budget_year_month,
    transaction_year,
    transaction_month,
    net_cash_flow,
    savings_rate_percent,

    -- Generate suggestions based on variance patterns
    CASE
      WHEN net_cash_flow < 0 THEN 'Critical'
      WHEN savings_rate_percent < 0.05 THEN 'High'
      ELSE 'Medium'
    END AS adjustment_priority,

    -- Build suggestion text with key metrics
    CASE
      WHEN net_cash_flow < 0 THEN
        'Cash flow is negative: reduce total expenses by $' || ROUND(ABS(net_cash_flow), 0)::text
      WHEN savings_rate_percent < 0.05 THEN
        'Savings rate is below 5%: target 15-20% by reducing discretionary spending'
      WHEN total_expenses > target_expenses * 1.1 THEN
        'Total expenses are 10%+ above 3-month target: review category overruns starting with Mortgage and Household'
      ELSE
        'Monitor spending in categories that exceed target by >10%'
    END AS suggestion_text,

    -- Next steps
    CASE
      WHEN net_cash_flow < 0 THEN
        'Review all expense categories and defer non-essential spending'
      WHEN savings_rate_percent < 0.05 THEN
        'Prioritize reducing Food & Drink and Household & Services spend'
      WHEN total_expenses > target_expenses * 1.1 THEN
        'Create specific spending targets for over-budget categories'
      ELSE
        'Continue current spending patterns with watchful monitoring'
    END AS recommended_action,

    -- Expected impact
    ROUND(
      CASE
        WHEN total_expenses > target_expenses * 1.1 THEN (total_expenses - target_expenses) * 0.5
        WHEN total_expenses > target_expenses * 1.05 THEN (total_expenses - target_expenses) * 0.75
        ELSE 0
      END, 2
    ) AS potential_monthly_savings

  FROM suggestions_base
)

SELECT
  budget_year_month,
  transaction_year,
  transaction_month,
  adjustment_priority,
  suggestion_text,
  recommended_action,
  ROUND(net_cash_flow, 2) AS current_net_cash_flow,
  ROUND(savings_rate_percent * 100, 1) AS current_savings_rate_pct,
  potential_monthly_savings,

  -- Formatted values
  '$' || TO_CHAR(net_cash_flow::numeric, 'FM999,999,999') AS net_cash_flow_formatted,
  '$' || TO_CHAR(potential_monthly_savings::numeric, 'FM999,999,999') AS potential_savings_formatted,

  CURRENT_TIMESTAMP AS report_generated_at

FROM suggestions_unpacked
ORDER BY
  CASE adjustment_priority WHEN 'Critical' THEN 1 WHEN 'High' THEN 2 ELSE 3 END,
  potential_monthly_savings DESC
