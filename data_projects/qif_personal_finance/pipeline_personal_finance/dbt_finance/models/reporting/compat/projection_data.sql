{{ config(materialized='view') }}

SELECT
  projection_date,
  scenario,
  projection_month,
  projected_monthly_income,
  projected_monthly_expenses,
  projected_net_flow,
  cumulative_net_flow,
  projected_savings_rate
FROM {{ ref('fct_financial_projections') }}
