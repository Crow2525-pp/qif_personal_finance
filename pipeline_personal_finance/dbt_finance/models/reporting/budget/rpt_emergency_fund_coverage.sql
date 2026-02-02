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

WITH available_months AS (
  -- Anchor to overlapping months present in both sources to avoid NULL coverage
  SELECT
    GREATEST(nw.min_month, mb.min_month) AS min_month,
    LEAST(nw.max_month, mb.max_month) AS max_month
  FROM (
    SELECT MIN(budget_year_month) AS min_month, MAX(budget_year_month) AS max_month
    FROM {{ ref('rpt_household_net_worth') }}
  ) nw
  CROSS JOIN (
    SELECT MIN(budget_year_month) AS min_month, MAX(budget_year_month) AS max_month
    FROM {{ ref('rpt_monthly_budget_summary') }}
  ) mb
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

expense_history AS (
  SELECT
    budget_year_month,
    total_expenses,
    -- Essential expenses approximation (mortgage + household + food + family + health)
    mortgage_expenses + household_expenses + food_expenses + family_expenses AS essential_expenses,
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
    AVG(total_expenses) AS avg_monthly_expenses,
    AVG(essential_expenses) AS avg_monthly_essential_expenses,
    AVG(mortgage_expenses) AS avg_mortgage,
    AVG(household_expenses) AS avg_household,
    AVG(food_expenses) AS avg_food,
    AVG(family_expenses) AS avg_family
  FROM expense_history
),

emergency_fund_calc AS (
  SELECT
    nw.budget_year_month,
    nw.liquid_assets,
    nw.total_assets,
    nw.net_worth,
    ae.avg_monthly_expenses,
    ae.avg_monthly_essential_expenses,

    -- Months of total expenses covered
    CASE
      WHEN ae.avg_monthly_expenses > 0
      THEN ROUND((nw.liquid_assets / ae.avg_monthly_expenses)::numeric, 1)
      ELSE 0
    END AS months_total_expenses_covered,

    -- Months of essential expenses covered (more conservative)
    CASE
      WHEN ae.avg_monthly_essential_expenses > 0
      THEN ROUND((nw.liquid_assets / ae.avg_monthly_essential_expenses)::numeric, 1)
      ELSE 0
    END AS months_essential_expenses_covered,

    -- Target coverage (6 months for family with young kids)
    6.0 AS target_months_coverage,

    -- Gap to target
    CASE
      WHEN ae.avg_monthly_essential_expenses > 0
      THEN ROUND((6.0 * ae.avg_monthly_essential_expenses - nw.liquid_assets)::numeric, 2)
      ELSE 0
    END AS gap_to_target_dollars,

    -- Category breakdown for display
    ae.avg_mortgage AS monthly_mortgage,
    ae.avg_household AS monthly_household,
    ae.avg_food AS monthly_food,
    ae.avg_family AS monthly_family

  FROM latest_net_worth nw
  CROSS JOIN avg_expenses ae
)

SELECT
  budget_year_month,
  liquid_assets,
  avg_monthly_expenses,
  avg_monthly_essential_expenses,
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
