{{ config(materialized='view') }}

SELECT
  account_key AS origin_key,
  CASE
    WHEN LOWER(account_type) LIKE '%home loan%' THEN 'homeloan'
    WHEN LOWER(account_type) LIKE '%offset%' THEN 'offset'
    WHEN LOWER(account_type) LIKE '%bills%' THEN 'bills'
    WHEN LOWER(account_type) LIKE '%everyday%' THEN 'countdown'
    ELSE LOWER(REPLACE(account_name, '_', ''))
  END AS account_name,
  LOWER(SPLIT_PART(bank_name, ' ', 1)) AS bank_name
FROM {{ ref('dim_accounts') }}
