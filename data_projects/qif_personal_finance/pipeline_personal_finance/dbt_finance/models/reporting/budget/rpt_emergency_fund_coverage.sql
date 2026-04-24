{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['budget_year_month'], 'unique': true}
    ]
  )
}}

/*
  Emergency Fund Coverage Analysis
  Calculates how many months of essential expenses are covered by liquid assets.
  Target: 3-6 months coverage for a family with young children.
*/

WITH net_worth_bounds AS (
  SELECT
    MIN(budget_year_month) AS min_month,
    MAX(budget_year_month) AS max_month
  FROM {{ ref('rpt_household_net_worth') }}
  WHERE budget_year_month < TO_CHAR(CURRENT_DATE, 'YYYY-MM')
),

budget_bounds AS (
  SELECT
    MIN(budget_year_month) AS min_month,
    MAX(budget_year_month) AS max_month
  FROM {{ ref('rpt_monthly_budget_summary') }}
  WHERE budget_year_month < TO_CHAR(CURRENT_DATE, 'YYYY-MM')
),

available_months AS (
  -- Anchor to overlapping completed months present in both sources
  SELECT
    GREATEST(nw.min_month, mb.min_month) AS min_month,
    LEAST(nw.max_month, mb.max_month) AS max_month
  FROM net_worth_bounds nw
  CROSS JOIN budget_bounds mb
),

latest_net_worth AS (
  SELECT
    budget_year_month,
    liquid_assets,
    total_assets,
    net_worth
  FROM {{ ref('rpt_household_net_worth') }}
  WHERE budget_year_month = (SELECT max_month FROM available_months)
  ORDER BY budget_year_month DESC
  LIMIT 1
),

latest_expenses AS (
  SELECT
    budget_year_month,
    COALESCE(total_expenses, 0) AS total_expenses_last_month,
    COALESCE(mortgage_expenses, 0) + COALESCE(household_expenses, 0) + COALESCE(food_expenses, 0) + COALESCE(family_expenses, 0) AS essential_expenses_last_month,
    COALESCE(mortgage_expenses, 0) AS mortgage_expenses_last_month,
    COALESCE(household_expenses, 0) AS household_expenses_last_month,
    COALESCE(food_expenses, 0) AS food_expenses_last_month,
    COALESCE(family_expenses, 0) AS family_expenses_last_month
  FROM {{ ref('rpt_monthly_budget_summary') }}
  WHERE budget_year_month = (SELECT max_month FROM available_months)
  ORDER BY budget_year_month DESC
  LIMIT 1
),

expense_history_6m AS (
  SELECT
    budget_year_month,
    total_expenses,
    -- Essential expenses approximation (mortgage + household + food + family + health)
    COALESCE(mortgage_expenses, 0) + COALESCE(household_expenses, 0) + COALESCE(food_expenses, 0) + COALESCE(family_expenses, 0) AS essential_expenses,
    -- Individual category breakdowns
    mortgage_expenses,
    household_expenses,
    food_expenses,
    family_expenses
  FROM {{ ref('rpt_monthly_budget_summary') }}
  WHERE budget_year_month BETWEEN (SELECT min_month FROM available_months) AND (SELECT max_month FROM available_months)
  ORDER BY budget_year_month DESC
  LIMIT 6
),

avg_expenses AS (
  SELECT
    ROUND(AVG(total_expenses)::numeric, 2) AS avg_monthly_expenses_6m,
    ROUND(AVG(essential_expenses)::numeric, 2) AS avg_monthly_essential_expenses_6m
  FROM expense_history_6m
),

emergency_fund_calc AS (
  SELECT
    nw.budget_year_month,
    nw.liquid_assets,
    nw.total_assets,
    nw.net_worth,
    le.total_expenses_last_month,
    le.essential_expenses_last_month,
    ae.avg_monthly_expenses_6m,
    ae.avg_monthly_essential_expenses_6m,

    -- Months of total expenses covered
    CASE
      WHEN le.total_expenses_last_month > 0
      THEN ROUND((nw.liquid_assets / le.total_expenses_last_month)::numeric, 1)
      ELSE 0
    END AS months_total_expenses_covered,

    -- Months of essential expenses covered (conservative, based on latest month)
    CASE
      WHEN le.essential_expenses_last_month > 0
      THEN ROUND((nw.liquid_assets / NULLIF(le.essential_expenses_last_month, 0))::numeric, 1)
      ELSE 0
    END AS months_essential_expenses_covered,

    -- Target coverage (6 months for family with young kids)
    6.0 AS target_months_coverage,

    -- Gap to target
    CASE
      WHEN le.essential_expenses_last_month > 0
      THEN ROUND((6.0 * le.essential_expenses_last_month - nw.liquid_assets)::numeric, 2)
      ELSE 0
    END AS gap_to_target_dollars,

    -- Category breakdown for display (latest month actuals)
    le.mortgage_expenses_last_month AS monthly_mortgage,
    le.household_expenses_last_month AS monthly_household,
    le.food_expenses_last_month AS monthly_food,
    le.family_expenses_last_month AS monthly_family

  FROM latest_net_worth nw
  CROSS JOIN latest_expenses le
  CROSS JOIN avg_expenses ae
)

SELECT
  budget_year_month,
  liquid_assets,
  total_expenses_last_month AS avg_monthly_expenses,
  essential_expenses_last_month AS avg_monthly_essential_expenses,
  avg_monthly_expenses_6m,
  avg_monthly_essential_expenses_6m,
  COALESCE(months_total_expenses_covered, 0) AS months_total_expenses_covered,
  COALESCE(months_essential_expenses_covered, 0) AS months_essential_expenses_covered,
  target_months_coverage,
  gap_to_target_dollars,

  -- Status indicator for gauge
  CASE
    WHEN months_essential_expenses_covered >= 6 THEN 'Excellent'
    WHEN months_essential_expenses_covered >= 3 THEN 'Good'
    WHEN months_essential_expenses_covered >= 1 THEN 'Low'
    ELSE 'Critical'
  END AS coverage_status,

  -- Progress percentage toward target (capped at 100%)
  LEAST(1.0, months_essential_expenses_covered / target_months_coverage) AS progress_to_target,

  -- Essential expense breakdown
  monthly_mortgage,
  monthly_household,
  monthly_food,
  monthly_family,

  CURRENT_TIMESTAMP AS report_generated_at

FROM emergency_fund_calc
