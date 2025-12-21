-- Test that account balances are continuous (no gaps in running balance calculation)
WITH balance_changes AS (
  SELECT 
    account_name,
    transaction_date,
    adjusted_transaction_balance,
    LAG(adjusted_transaction_balance) OVER (
      PARTITION BY account_name 
      ORDER BY transaction_date, line_number
    ) AS previous_balance,
    transaction_amount
  FROM {{ ref('int_account_balances') }}
),

balance_discrepancies AS (
  SELECT 
    account_name,
    transaction_date,
    adjusted_transaction_balance,
    previous_balance,
    transaction_amount,
    -- Check if current balance equals previous balance plus current transaction
    ABS((previous_balance + transaction_amount) - adjusted_transaction_balance) AS balance_diff
  FROM balance_changes
  WHERE previous_balance IS NOT NULL
)

SELECT *
FROM balance_discrepancies
WHERE balance_diff > 0.01 -- Allow for small rounding differences