-- Test that all accounts in fact table exist in account dimension
WITH account_integrity AS (
  SELECT 
    ft.account_key,
    da.account_key AS dim_account_key,
    CASE 
      WHEN da.account_key IS NULL THEN 'MISSING_FROM_DIMENSION'
      ELSE 'VALID'
    END AS integrity_status
  FROM {{ ref('fct_transactions_enhanced') }} ft
  LEFT JOIN {{ ref('dim_accounts_enhanced') }} da
    ON ft.account_key = da.account_key
),

integrity_issues AS (
  SELECT 
    account_key,
    COUNT(*) AS transaction_count
  FROM account_integrity
  WHERE integrity_status = 'MISSING_FROM_DIMENSION'
  GROUP BY account_key
)

SELECT *
FROM integrity_issues