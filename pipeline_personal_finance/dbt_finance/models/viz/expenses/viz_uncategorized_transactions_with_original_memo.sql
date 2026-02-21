{{
  config(
    materialized='view'
  )
}}

WITH uncategorized_transactions AS (
  SELECT
    ft.transaction_date,
    ABS(ft.transaction_amount) AS amount_abs,
    COALESCE(
      NULLIF(TRIM(ft.transaction_memo), ''),
      NULLIF(TRIM(ft.transaction_description), '')
    ) AS standardized_memo,
    COALESCE(
      NULLIF(TRIM(ft.transaction_description), ''),
      NULLIF(TRIM(ft.transaction_memo), '')
    ) AS raw_merchant_text,
    da.account_name,
    da.bank_name,
    ft.transaction_type,
    ft.sender,
    ft.recipient,
    ft.location
  FROM {{ ref('fct_transactions') }} ft
  LEFT JOIN {{ ref('dim_accounts') }} da
    ON ft.account_key = da.account_key
  LEFT JOIN {{ ref('dim_categories') }} dc
    ON ft.category_key = dc.category_key
  WHERE dc.level_1_category = 'Uncategorized'
    AND ft.transaction_amount < 0
    AND NOT COALESCE(ft.is_internal_transfer, FALSE)
    AND COALESCE(
      NULLIF(TRIM(ft.transaction_description), ''),
      NULLIF(TRIM(ft.transaction_memo), '')
    ) IS NOT NULL
),

normalized_merchants AS (
  SELECT
    ut.*,
    TRIM(REGEXP_REPLACE(ut.raw_merchant_text, '\s+', ' ', 'g')) AS merchant_text_clean,
    COALESCE(
      NULLIF(
        LOWER(
          REGEXP_REPLACE(
            REGEXP_REPLACE(TRIM(ut.raw_merchant_text), '\d+', '', 'g'),
            '[^a-zA-Z]+',
            '',
            'g'
          )
        ),
        ''
      ),
      'unknownmerchant'
    ) AS merchant_key
  FROM uncategorized_transactions ut
),

prepared_merchants AS (
  SELECT
    nm.transaction_date,
    nm.amount_abs,
    nm.standardized_memo,
    nm.account_name,
    nm.bank_name,
    nm.transaction_type,
    nm.sender,
    nm.recipient,
    nm.location,
    nm.merchant_key,
    TRIM(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          COALESCE(NULLIF(nm.merchant_text_clean, ''), 'Unknown Merchant'),
          '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+',
          '[masked-email]',
          'g'
        ),
        '\d{4,}',
        '####',
        'g'
      )
    ) AS merchant_display_name
  FROM normalized_merchants nm
),

uncategorized_grouped AS (
  SELECT
    merchant_key,
    MIN(merchant_display_name) AS merchant_display_name,
    MIN(standardized_memo) AS standardized_memo,
    STRING_AGG(DISTINCT account_name, ', ' ORDER BY account_name) AS account_name,
    STRING_AGG(DISTINCT bank_name, ', ' ORDER BY bank_name) AS bank_name,
    STRING_AGG(DISTINCT transaction_type, ', ' ORDER BY transaction_type) AS transaction_type,
    STRING_AGG(DISTINCT sender, ', ' ORDER BY sender) AS sender,
    STRING_AGG(DISTINCT recipient, ', ' ORDER BY recipient) AS recipient,
    MIN(location) AS sample_location,
    COUNT(*) AS transaction_count,
    SUM(amount_abs) AS total_amount,
    AVG(amount_abs) AS avg_amount,
    MIN(transaction_date) AS first_transaction_date,
    MAX(transaction_date) AS last_transaction_date,
    STRING_AGG(amount_abs::text, ', ' ORDER BY transaction_date) AS all_amounts,
    STRING_AGG(transaction_date::text, ', ' ORDER BY transaction_date) AS all_dates
  FROM prepared_merchants
  GROUP BY merchant_key
),

total_uncategorized AS (
  SELECT COALESCE(SUM(total_amount), 0) AS total_uncategorized_amount
  FROM uncategorized_grouped
)

SELECT
  ug.merchant_key,
  ug.merchant_display_name,
  ug.merchant_display_name AS original_memo,
  ug.standardized_memo,
  ug.account_name,
  ug.bank_name,
  ug.transaction_type,
  ug.sender,
  ug.recipient,
  ug.sample_location,
  ug.total_amount,
  ug.transaction_count,
  ug.transaction_count AS txn_count,
  ug.avg_amount,
  CASE
    WHEN tu.total_uncategorized_amount > 0
    THEN (ug.total_amount / tu.total_uncategorized_amount) * 100
    ELSE 0
  END AS contribution_pct,
  ug.first_transaction_date,
  ug.last_transaction_date,
  ug.all_amounts,
  ug.all_dates,
  CASE
    WHEN ug.total_amount >= 1000 THEN 'HIGH'
    WHEN ug.total_amount >= 500 THEN 'MEDIUM'
    WHEN ug.total_amount >= 100 THEN 'LOW'
    ELSE 'MINOR'
  END AS priority_level
FROM uncategorized_grouped ug
CROSS JOIN total_uncategorized tu
WHERE ug.transaction_count >= 2 OR ug.total_amount >= 100
ORDER BY ug.total_amount DESC, ug.transaction_count DESC
