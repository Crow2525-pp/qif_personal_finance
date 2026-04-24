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
    CAST(
      CASE
        WHEN date IS NULL THEN NULL
        WHEN CAST(date AS TEXT) ~ '^[0-9]{8}$' THEN TO_DATE(CAST(date AS TEXT), 'YYYYMMDD')
        ELSE CAST(CAST(date AS TEXT) AS DATE)
      END AS DATE
    ) AS transaction_date,
    CAST(amount AS DOUBLE PRECISION) AS transaction_amount,
    CAST(line_number AS BIGINT) AS line_number,
    CAST('bendigo_homeloan' AS TEXT) AS account_name,
    CAST(memo AS TEXT) AS memo,
    CAST(memo AS TEXT) AS transaction_description,
    CAST(CASE
      WHEN CAST(memo AS TEXT) = 'INTEREST' THEN 'INTEREST'
      WHEN CAST(memo AS TEXT) = 'MONTHLY SERVICE FEE' THEN 'MONTHLY SERVICE FEE'
      WHEN CAST(memo AS TEXT) = 'TRANSFER 00538977991401' THEN 'TRANSFER'
      ELSE ''
    END AS TEXT) AS transaction_type,
    CAST('' AS TEXT) AS receipt,
    CAST('' AS TEXT) AS location,
    CAST('' AS TEXT) AS description_date,
    CAST('' AS TEXT) AS card_no,
    CAST('BANK_MORTGAGE' AS TEXT) AS sender,
    CAST('YOU' AS TEXT) AS recipient,
    CAST(CURRENT_DATE AS DATE) AS etl_date,
    CAST(CURRENT_TIME AS TIME) AS etl_time

  FROM {{ ref('mortgage_patch_data') }}
  WHERE CAST(bank_name AS TEXT) = 'Bendigo'
    AND CAST(account_name AS TEXT) = 'Homeloan'
),

combined AS (
  SELECT
    primary_key,
    receipt,
    location,
    description_date,
    card_no,
    sender,
    recipient,
    transaction_amount,
    line_number,
    account_name,
    transaction_date,
    memo,
    transaction_description,
    transaction_type,
    etl_date,
    etl_time
  FROM original_transactions
  UNION ALL
  SELECT
    primary_key,
    receipt,
    location,
    description_date,
    card_no,
    sender,
    recipient,
    transaction_amount,
    line_number,
    account_name,
    transaction_date,
    memo,
    transaction_description,
    transaction_type,
    etl_date,
    etl_time
  FROM patch_transactions
)

SELECT * FROM combined
ORDER BY transaction_date, line_number
