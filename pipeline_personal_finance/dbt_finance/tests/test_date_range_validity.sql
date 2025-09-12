-- Test that all transaction dates are within reasonable bounds
WITH date_validation AS (
  SELECT 
    transaction_date,
    transaction_natural_key,
    account_key,
    CASE 
      WHEN transaction_date < '2015-01-01' THEN 'TOO_OLD'
      WHEN transaction_date > CURRENT_DATE + INTERVAL '1 day' THEN 'FUTURE_DATE'
      ELSE 'VALID'
    END AS date_status
  FROM {{ ref('fct_transactions_enhanced') }}
),

invalid_dates AS (
  SELECT *
  FROM date_validation
  WHERE date_status != 'VALID'
)

SELECT *
FROM invalid_dates