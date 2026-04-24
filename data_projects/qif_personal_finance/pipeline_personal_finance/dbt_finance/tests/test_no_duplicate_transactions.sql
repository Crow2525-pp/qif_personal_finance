-- Test that there are no duplicate transactions across all staging models
WITH all_transactions AS (
  SELECT primary_key, account_name, transaction_date, transaction_amount, line_number
  FROM {{ ref('int_account_balances') }}
),

duplicate_check AS (
  SELECT 
    primary_key,
    account_name,
    transaction_date, 
    transaction_amount,
    COUNT(*) AS duplicate_count
  FROM all_transactions
  GROUP BY primary_key, account_name, transaction_date, transaction_amount
  HAVING COUNT(*) > 1
)

SELECT *
FROM duplicate_check