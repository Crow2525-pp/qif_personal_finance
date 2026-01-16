{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['merchant_pattern'], 'unique': false},
      {'columns': ['category'], 'unique': false}
    ]
  )
}}

-- Projects recurring bills due in the next month based on historical patterns
-- Helps with cash flow forecasting and planning

WITH recurring_base AS (
  SELECT
    merchant_pattern,
    category,
    subcategory,
    recurrence_type,
    estimated_monthly_cost,
    is_currently_active,
    possibly_cancelled,
    last_transaction_date,
    days_since_last_transaction,
    subscription_likelihood_score
  FROM {{ ref('rpt_recurring_transactions_analysis') }}
  WHERE is_currently_active = true
    AND possibly_cancelled = false
    AND recurrence_type IN ('Monthly', 'Quarterly', 'Semi-Annual', 'Annual')
    AND estimated_monthly_cost > 0
),

next_month_projection AS (
  SELECT
    merchant_pattern,
    category,
    subcategory,
    recurrence_type,
    estimated_monthly_cost,
    last_transaction_date,

    -- Calculate estimated due date (assume same day of month as last transaction)
    CASE
      WHEN EXTRACT(DAY FROM last_transaction_date) <= 28 THEN
        DATE_TRUNC('month', CURRENT_DATE + INTERVAL '1 month') +
        (EXTRACT(DAY FROM last_transaction_date) - 1) * INTERVAL '1 day'
      ELSE
        DATE_TRUNC('month', CURRENT_DATE + INTERVAL '1 month') +
        INTERVAL '1 month' - INTERVAL '1 day'  -- Last day of month
    END AS estimated_next_due_date,

    -- Days until due
    (
      CASE
        WHEN EXTRACT(DAY FROM last_transaction_date) <= 28 THEN
          DATE_TRUNC('month', CURRENT_DATE + INTERVAL '1 month') +
          (EXTRACT(DAY FROM last_transaction_date) - 1) * INTERVAL '1 day'
        ELSE
          DATE_TRUNC('month', CURRENT_DATE + INTERVAL '1 month') +
          INTERVAL '1 month' - INTERVAL '1 day'
      END
    ) - CURRENT_DATE AS days_until_due,

    -- Priority flag (bills due sooner should be higher priority)
    CASE
      WHEN EXTRACT(DAY FROM last_transaction_date) <= 7 THEN 'High'  -- Early in month
      WHEN EXTRACT(DAY FROM last_transaction_date) <= 14 THEN 'Medium'
      ELSE 'Low'
    END AS payment_priority,

    subscription_likelihood_score,
    is_currently_active

  FROM recurring_base
),

final_projection AS (
  SELECT
    merchant_pattern,
    category,
    subcategory,
    recurrence_type,
    ROUND(estimated_monthly_cost, 2) AS estimated_monthly_cost,
    estimated_next_due_date,
    days_until_due::INTEGER AS days_until_due,
    payment_priority,
    subscription_likelihood_score,
    ROUND(estimated_monthly_cost, 2) AS projected_next_month_impact,
    CURRENT_TIMESTAMP AS report_generated_at
  FROM next_month_projection
)

SELECT * FROM final_projection
ORDER BY days_until_due ASC, estimated_monthly_cost DESC
