WITH original_transactions AS (
  {{ stage_bank_transactions('Bendigo_Homeloan_Transactions', 'bendigo', 'homeloan') }}
),

-- Include patch data from seed table
patch_transactions AS (
  SELECT
    -- Standardized transaction identifiers  
    primary_key,
    CAST(date AS DATE) AS transaction_date,
    CAST(amount AS FLOAT) AS transaction_amount,
    line_number,
    
    -- Account information
    'bendigo_homeloan' AS account_name,
    
    -- Memo and extracted details
    memo,
    '' AS transaction_description,
    CASE 
      WHEN memo = 'INTEREST' THEN 'INTEREST'
      WHEN memo = 'MONTHLY SERVICE FEE' THEN 'MONTHLY SERVICE FEE'  
      WHEN memo = 'TRANSFER 00538977991401' THEN 'TRANSFER'
      ELSE ''
    END AS transaction_type,
    
    -- Placeholder fields for consistency
    '' AS receipt,
    '' AS location,
    '' AS description_date, 
    '' AS card_no,
    '' AS sender,
    '' AS recipient,
    
    -- ETL metadata
    CURRENT_DATE AS etl_date,
    CURRENT_TIME AS etl_time
  
  FROM {{ ref('mortgage_patch_data') }}
  WHERE bank_name = 'Bendigo' 
    AND account_name = 'Homeloan'
),

combined AS (
  SELECT * FROM original_transactions
  UNION ALL
  SELECT * FROM patch_transactions
)

SELECT * FROM combined
ORDER BY transaction_date, line_number
