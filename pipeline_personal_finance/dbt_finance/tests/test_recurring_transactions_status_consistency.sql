SELECT
  merchant_pattern,
  recurrence_type,
  last_transaction_date,
  days_since_last_transaction
FROM {{ ref('rpt_recurring_transactions_analysis') }}
WHERE is_currently_active
  AND possibly_cancelled
