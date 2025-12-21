-- Fails when mortgage interest transactions are not categorized as Mortgage
WITH base AS (
  SELECT 
    ft.transaction_key,
    ft.transaction_date,
    ft.transaction_type,
    ft.transaction_memo,
    ft.transaction_amount,
    ft.is_internal_transfer,
    da.account_name,
    da.is_mortgage,
    dc.level_1_category,
    dc.level_2_subcategory,
    dc.level_3_store,
    {{ metric_interest_payment('ft', 'dc') }} AS interest_amount
  FROM {{ ref('fct_transactions_enhanced') }} ft
  LEFT JOIN {{ ref('dim_accounts_enhanced') }} da
    ON ft.account_key = da.account_key
  LEFT JOIN {{ ref('dim_categories_enhanced') }} dc
    ON ft.category_key = dc.category_key
)
SELECT 
  transaction_key,
  transaction_date,
  account_name,
  transaction_type,
  transaction_memo,
  level_1_category,
  level_2_subcategory,
  level_3_store,
  transaction_amount,
  interest_amount
FROM base
WHERE is_mortgage = TRUE
  AND (
    UPPER(COALESCE(transaction_type, '')) IN ('DEBIT INTEREST', 'INTEREST')
     OR LOWER(COALESCE(level_2_subcategory, '')) LIKE '%interest%'
     OR LOWER(COALESCE(level_3_store, '')) LIKE '%interest%'
  )
  AND (
    level_1_category <> 'Mortgage'
     OR COALESCE(is_internal_transfer, FALSE)
     OR interest_amount = 0
  )
