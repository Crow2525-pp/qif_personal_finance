-- Validates metric_expense() aligns with raw signs and flags
WITH base AS (
  SELECT
    ft.transaction_key,
    ft.transaction_amount,
    ft.is_income_transaction,
    ft.is_internal_transfer,
    ft.is_financial_service,
    dc.level_1_category,
    {{ metric_expense(false, 'ft', 'dc') }} AS expense_amount
  FROM {{ ref('fct_transactions') }} ft
  LEFT JOIN {{ ref('dim_categories') }} dc
    ON ft.category_key = dc.category_key
)
SELECT
  transaction_key,
  transaction_amount,
  is_income_transaction,
  is_internal_transfer,
  is_financial_service,
  level_1_category,
  expense_amount
FROM base
WHERE
  -- Expect positive expense when negative outflow, not income, not internal, not financial service
  (
    transaction_amount < 0
    AND NOT COALESCE(is_income_transaction, FALSE)
    AND NOT COALESCE(is_internal_transfer, FALSE)
    AND NOT COALESCE(is_financial_service, FALSE)
    AND ABS(transaction_amount) != expense_amount
  )
  OR
  -- Expect zero expense otherwise
  (
    NOT (
      transaction_amount < 0
      AND NOT COALESCE(is_income_transaction, FALSE)
      AND NOT COALESCE(is_internal_transfer, FALSE)
      AND NOT COALESCE(is_financial_service, FALSE)
    )
    AND expense_amount != 0
  )
