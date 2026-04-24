{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['budget_year_month', 'driver'], 'unique': true}
    ]
  )
}}

-- Month-over-Month Cash Flow Waterfall Drivers
-- Calculates deltas between selected and previous month for income, expenses, transfers, and net cash flow
-- Output format designed for waterfall visualizations showing what drove the change in net cash flow

WITH available_months AS (
  SELECT budget_year_month,
         to_date(budget_year_month || '-01', 'YYYY-MM-DD') AS month_date
  FROM {{ ref('rpt_monthly_budget_summary') }}
  WHERE budget_year_month < TO_CHAR(CURRENT_DATE, 'YYYY-MM')
),

-- Get current month data from both budget summary and cash flow analysis
current_month AS (
  SELECT
    bs.budget_year_month,
    bs.total_income,
    bs.total_expenses,
    bs.net_cash_flow,
    cf.total_internal_transfers,
    to_date(bs.budget_year_month || '-01', 'YYYY-MM-DD') AS month_date
  FROM {{ ref('rpt_monthly_budget_summary') }} bs
  LEFT JOIN {{ ref('rpt_cash_flow_analysis') }} cf
    ON bs.budget_year_month = cf.budget_year_month
),

-- Get previous month data
previous_month AS (
  SELECT
    cm.budget_year_month AS current_month_key,
    bs.total_income AS prev_income,
    bs.total_expenses AS prev_expenses,
    bs.net_cash_flow AS prev_net_cash_flow,
    cf.total_internal_transfers AS prev_internal_transfers
  FROM current_month cm
  CROSS JOIN LATERAL (
    SELECT budget_year_month,
           to_date(budget_year_month || '-01', 'YYYY-MM-DD') AS month_date
    FROM available_months
    WHERE month_date < cm.month_date
    ORDER BY month_date DESC
    LIMIT 1
  ) prev_month
  LEFT JOIN {{ ref('rpt_monthly_budget_summary') }} bs
    ON prev_month.budget_year_month = bs.budget_year_month
  LEFT JOIN {{ ref('rpt_cash_flow_analysis') }} cf
    ON prev_month.budget_year_month = cf.budget_year_month
),

-- Calculate deltas for waterfall
waterfall_deltas AS (
  SELECT
    cm.budget_year_month,
    cm.month_date,

    -- Current month values
    cm.total_income AS current_income,
    cm.total_expenses AS current_expenses,
    cm.total_internal_transfers AS current_internal_transfers,
    cm.net_cash_flow AS current_net_cash_flow,

    -- Previous month values
    COALESCE(pm.prev_income, 0) AS previous_income,
    COALESCE(pm.prev_expenses, 0) AS previous_expenses,
    COALESCE(pm.prev_internal_transfers, 0) AS previous_internal_transfers,
    COALESCE(pm.prev_net_cash_flow, 0) AS previous_net_cash_flow,

    -- Delta calculations for waterfall
    -- Income increase = positive contribution to net cash flow
    cm.total_income - COALESCE(pm.prev_income, 0) AS income_delta,

    -- Expense increase = negative contribution (hence the negation)
    -- If expenses increased, this will be negative; if decreased, positive
    -(cm.total_expenses - COALESCE(pm.prev_expenses, 0)) AS expense_delta,

    -- Transfer change (net impact on cash position)
    COALESCE(cm.total_internal_transfers, 0) - COALESCE(pm.prev_internal_transfers, 0) AS transfers_delta,

    -- Net delta (should equal sum of above deltas)
    cm.net_cash_flow - COALESCE(pm.prev_net_cash_flow, 0) AS net_delta,

    CURRENT_TIMESTAMP AS report_generated_at

  FROM current_month cm
  LEFT JOIN previous_month pm
    ON cm.budget_year_month = pm.current_month_key
)

-- Unpivot deltas into rows for waterfall visualization
SELECT
  budget_year_month,
  month_date,

  -- Row 1: Income contribution
  'Income' AS driver,
  1 AS sort_order,
  income_delta AS delta_amount,
  current_income,
  previous_income,

  -- Metadata
  report_generated_at

FROM waterfall_deltas

UNION ALL

-- Row 2: Expense contribution (already negated)
SELECT
  budget_year_month,
  month_date,
  'Expenses' AS driver,
  2 AS sort_order,
  expense_delta AS delta_amount,
  current_expenses,
  previous_expenses,
  report_generated_at

FROM waterfall_deltas

UNION ALL

-- Row 3: Transfers contribution
SELECT
  budget_year_month,
  month_date,
  'Transfers' AS driver,
  3 AS sort_order,
  transfers_delta AS delta_amount,
  current_internal_transfers,
  previous_internal_transfers,
  report_generated_at

FROM waterfall_deltas

UNION ALL

-- Row 4: Net result
SELECT
  budget_year_month,
  month_date,
  'Net Change' AS driver,
  4 AS sort_order,
  net_delta AS delta_amount,
  current_net_cash_flow AS current_income,
  previous_net_cash_flow AS previous_income,
  report_generated_at

FROM waterfall_deltas

ORDER BY budget_year_month DESC, sort_order
