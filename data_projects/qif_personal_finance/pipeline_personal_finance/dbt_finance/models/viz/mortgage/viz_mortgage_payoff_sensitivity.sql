{{
  config(
    materialized='view'
  )
}}

-- Payoff sensitivity analysis: for a range of extra monthly payments,
-- calculates how many years until the mortgage is fully paid off.
-- Uses the current balance and average monthly principal from viz_mortgage_payoff_summary.

WITH summary AS (
  SELECT *
  FROM {{ ref('viz_mortgage_payoff_summary') }}
),

scenario_inputs AS (
  SELECT 0::numeric   AS extra_payment
  UNION ALL SELECT 100
  UNION ALL SELECT 250
  UNION ALL SELECT 500
  UNION ALL SELECT 1000
)

SELECT
  extra_payment::int                                          AS sort_order,
  '$' || TRIM(TO_CHAR(extra_payment, 'FM9999990'))            AS extra_payment_label,
  ROUND(
    (
      (SELECT current_mortgage_balance FROM summary)
      / NULLIF(
          (SELECT avg_monthly_principal_reduction FROM summary) + extra_payment,
          0
        )
    ) / 12.0,
    1
  )                                                           AS years_to_payoff
FROM scenario_inputs s
ORDER BY sort_order
