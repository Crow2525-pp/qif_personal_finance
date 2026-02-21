{{
  config(
    materialized='view'
  )
}}

-- Single-row summary of the current mortgage position and payoff projection.
-- Derives the average monthly principal reduction from the last 12 months
-- of viz_mortgage_payoff_monthly and projects years to payoff and payoff year.

WITH monthly AS (
  SELECT *
  FROM {{ ref('viz_mortgage_payoff_monthly') }}
),

latest AS (
  SELECT
    month_start,
    mortgage_balance,
    offset_balance,
    net_mortgage_exposure,
    data_note,
    homeloan_latest_date,
    offset_latest_date
  FROM monthly
  WHERE mortgage_balance IS NOT NULL
  ORDER BY month_start DESC
  LIMIT 1
),

reductions AS (
  SELECT
    month_start,
    mortgage_balance,
    GREATEST(
      COALESCE(
        LAG(mortgage_balance) OVER (ORDER BY month_start) - mortgage_balance,
        0
      ),
      0
    ) AS principal_reduction
  FROM monthly
  WHERE mortgage_balance IS NOT NULL
),

avg_reduction AS (
  SELECT
    COALESCE(
      NULLIF(AVG(NULLIF(principal_reduction, 0)), 0),
      1  -- fallback to 1 to avoid division by zero
    ) AS avg_monthly_principal_reduction
  FROM (
    SELECT principal_reduction
    FROM reductions
    ORDER BY month_start DESC
    LIMIT 12
  ) x
),

calc AS (
  SELECT
    l.month_start                                                AS data_through_month,
    l.mortgage_balance                                           AS current_mortgage_balance,
    l.offset_balance                                             AS current_offset_balance,
    l.net_mortgage_exposure,
    a.avg_monthly_principal_reduction,
    ROUND(
      (l.mortgage_balance / NULLIF(a.avg_monthly_principal_reduction, 0)) / 12.0,
      1
    )                                                            AS years_to_payoff,
    EXTRACT(
      YEAR FROM CURRENT_DATE
        + (CEIL(l.mortgage_balance / NULLIF(a.avg_monthly_principal_reduction, 0))::int
           * INTERVAL '1 month')
    )                                                            AS estimated_payoff_year,
    l.data_note,
    l.homeloan_latest_date,
    l.offset_latest_date
  FROM latest l
  CROSS JOIN avg_reduction a
)

SELECT
  data_through_month,
  current_mortgage_balance,
  current_offset_balance,
  net_mortgage_exposure,
  avg_monthly_principal_reduction,
  years_to_payoff,
  estimated_payoff_year,
  data_note,
  homeloan_latest_date,
  offset_latest_date,
  NOW() AT TIME ZONE 'Australia/Melbourne' AS report_generated_at
FROM calc
