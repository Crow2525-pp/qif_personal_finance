-- Test that all foreign key relationships are valid

-- Test 1: fct_transactions_enhanced.account_key references valid dim_accounts_enhanced.account_key
WITH invalid_account_references AS (
  SELECT 
    ft.transaction_key,
    ft.account_key,
    'Missing account reference' AS error_type
  FROM {{ ref('fct_transactions_enhanced') }} ft
  LEFT JOIN {{ ref('dim_accounts_enhanced') }} da
    ON ft.account_key = da.account_key
  WHERE da.account_key IS NULL
    AND ft.account_key IS NOT NULL
),

-- Test 2: fct_transactions_enhanced.category_key references valid dim_categories_enhanced.category_key  
invalid_category_references AS (
  SELECT 
    ft.transaction_key,
    ft.category_key,
    'Missing category reference' AS error_type
  FROM {{ ref('fct_transactions_enhanced') }} ft
  LEFT JOIN {{ ref('dim_categories_enhanced') }} dc
    ON ft.category_key = dc.category_key
  WHERE dc.category_key IS NULL
    AND ft.category_key IS NOT NULL
),

-- Test 3: fct_daily_balances.account_key references valid dim_accounts_enhanced.account_key
invalid_daily_balance_references AS (
  SELECT 
    fdb.account_key,
    fdb.balance_date,
    'Missing account reference in daily balances' AS error_type
  FROM {{ ref('fct_daily_balances') }} fdb
  LEFT JOIN {{ ref('dim_accounts_enhanced') }} da
    ON fdb.account_key = da.account_key  
  WHERE da.account_key IS NULL
    AND fdb.account_key IS NOT NULL
),

-- Combine all violations
all_violations AS (
  SELECT transaction_key AS record_key, account_key AS foreign_key_value, error_type
  FROM invalid_account_references
  
  UNION ALL
  
  SELECT transaction_key AS record_key, category_key AS foreign_key_value, error_type  
  FROM invalid_category_references
  
  UNION ALL
  
  SELECT balance_date::TEXT AS record_key, account_key AS foreign_key_value, error_type
  FROM invalid_daily_balance_references
)

-- Return violations (test fails if any exist)
SELECT * FROM all_violations