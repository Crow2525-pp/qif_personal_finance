{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['budget_year_month'], 'unique': true},
      {'columns': ['budget_year'], 'unique': false}
    ]
  )
}}

WITH budget_targets AS (
  -- Calculate 3-month rolling average as budget targets
  SELECT
    transaction_year,
    transaction_month,
    transaction_year || '-' || LPAD(transaction_month::TEXT, 2, '0') AS budget_year_month,

    -- Rolling 3-month average targets (excluding current month)
    AVG(total_income) OVER (
      ORDER BY transaction_year, transaction_month
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS target_income,

    AVG(total_expenses) OVER (
      ORDER BY transaction_year, transaction_month
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS target_expenses,

    -- Category-level targets
    AVG(mortgage_expenses) OVER (
      ORDER BY transaction_year, transaction_month
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS target_mortgage,

    AVG(household_expenses) OVER (
      ORDER BY transaction_year, transaction_month
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS target_household,

    AVG(food_expenses) OVER (
      ORDER BY transaction_year, transaction_month
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS target_food,

    AVG(family_expenses) OVER (
      ORDER BY transaction_year, transaction_month
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS target_family,

    total_income,
    total_expenses,
    mortgage_expenses,
    household_expenses,
    food_expenses,
    family_expenses,
    net_cash_flow,
    savings_rate_percent

  FROM {{ ref('rpt_monthly_budget_summary') }}
),

variance_calculation AS (
  SELECT
    budget_year_month,
    transaction_year,
    transaction_month,

    -- Income variance
    total_income,
    target_income,
    CASE WHEN target_income > 0 THEN total_income - target_income ELSE 0 END AS income_variance_delta,
    CASE WHEN target_income > 0
      THEN ROUND(((total_income - target_income) / target_income) * 100, 1)
      ELSE 0
    END AS income_variance_pct,

    -- Expense variance
    total_expenses,
    target_expenses,
    CASE WHEN target_expenses > 0 THEN target_expenses - total_expenses ELSE 0 END AS expense_variance_delta,
    CASE WHEN target_expenses > 0
      THEN ROUND(((target_expenses - total_expenses) / target_expenses) * 100, 1)
      ELSE 0
    END AS expense_variance_pct,

    -- Category variances (over = positive for expenses)
    mortgage_expenses,
    target_mortgage,
    CASE WHEN target_mortgage > 0 THEN target_mortgage - mortgage_expenses ELSE 0 END AS mortgage_variance_delta,
    CASE WHEN target_mortgage > 0
      THEN ROUND(((target_mortgage - mortgage_expenses) / target_mortgage) * 100, 1)
      ELSE 0
    END AS mortgage_variance_pct,

    household_expenses,
    target_household,
    CASE WHEN target_household > 0 THEN target_household - household_expenses ELSE 0 END AS household_variance_delta,
    CASE WHEN target_household > 0
      THEN ROUND(((target_household - household_expenses) / target_household) * 100, 1)
      ELSE 0
    END AS household_variance_pct,

    food_expenses,
    target_food,
    CASE WHEN target_food > 0 THEN target_food - food_expenses ELSE 0 END AS food_variance_delta,
    CASE WHEN target_food > 0
      THEN ROUND(((target_food - food_expenses) / target_food) * 100, 1)
      ELSE 0
    END AS food_variance_pct,

    family_expenses,
    target_family,
    CASE WHEN target_family > 0 THEN target_family - family_expenses ELSE 0 END AS family_variance_delta,
    CASE WHEN target_family > 0
      THEN ROUND(((target_family - family_expenses) / target_family) * 100, 1)
      ELSE 0
    END AS family_variance_pct,

    net_cash_flow,
    savings_rate_percent

  FROM budget_targets
)

SELECT
  budget_year_month,
  transaction_year,
  transaction_month,

  -- Income metrics with variance
  total_income,
  ROUND(target_income, 2) AS target_income,
  income_variance_delta,
  income_variance_pct,

  -- Expense metrics with variance
  total_expenses,
  ROUND(target_expenses, 2) AS target_expenses,
  expense_variance_delta,
  expense_variance_pct,

  -- Category-level variance metrics
  mortgage_expenses,
  ROUND(target_mortgage, 2) AS target_mortgage,
  mortgage_variance_delta,
  mortgage_variance_pct,

  household_expenses,
  ROUND(target_household, 2) AS target_household,
  household_variance_delta,
  household_variance_pct,

  food_expenses,
  ROUND(target_food, 2) AS target_food,
  food_variance_delta,
  food_variance_pct,

  family_expenses,
  ROUND(target_family, 2) AS target_family,
  family_variance_delta,
  family_variance_pct,

  -- Summary metrics
  net_cash_flow,
  savings_rate_percent,

  -- Variance status indicators
  CASE
    WHEN income_variance_pct < -10 THEN 'Below Target'
    WHEN income_variance_pct > 10 THEN 'Above Target'
    ELSE 'On Target'
  END AS income_status,

  CASE
    WHEN expense_variance_pct < -10 THEN 'Under Budget'
    WHEN expense_variance_pct > 10 THEN 'Over Budget'
    ELSE 'On Budget'
  END AS expense_status,

  CURRENT_TIMESTAMP AS report_generated_at

FROM variance_calculation
WHERE to_date(budget_year_month || '-01', 'YYYY-MM-DD') < date_trunc('month', CURRENT_DATE)
ORDER BY transaction_year DESC, transaction_month DESC
