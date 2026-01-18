WITH original_transactions AS (
  {{ stage_bank_transactions('Bendigo_Homeloan_Transactions', 'bendigo', 'homeloan') }}
),

-- Include patch data from seed table
patch_transactions AS (
  SELECT
    -- Standardized transaction identifiers
    CAST({{ dbt_utils.generate_surrogate_key([
      'date',
      'amount',
      'line_number',
      'memo',
      'bank_name',
      'account_name'
    ]) }} AS TEXT) AS primary_key,
    CAST('' AS TEXT) AS receipt,
    CAST('' AS TEXT) AS location,
    CAST('' AS TEXT) AS description_date,
    CAST('' AS TEXT) AS card_no,
    CAST('BANK_MORTGAGE' AS TEXT) AS sender,
    CAST('YOU' AS TEXT) AS recipient,
    CAST(amount AS DOUBLE) AS transaction_amount,
    CAST(line_number AS BIGINT) AS line_number,
    CAST('bendigo_homeloan' AS TEXT) AS account_name,
    CAST(date AS DATE) AS transaction_date,
    CAST(memo AS TEXT) AS memo,
    CAST(memo AS TEXT) AS transaction_description,
    CAST(CASE
      WHEN memo = 'INTEREST' THEN 'INTEREST'
      WHEN memo = 'MONTHLY SERVICE FEE' THEN 'MONTHLY SERVICE FEE'
      WHEN memo = 'TRANSFER 00538977991401' THEN 'TRANSFER'
      ELSE ''
    END AS TEXT) AS transaction_type,
    CAST(CURRENT_DATE AS DATE) AS etl_date,
    CAST(CURRENT_TIME AS TIME) AS etl_time

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
