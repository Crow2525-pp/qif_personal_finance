{{ config(materialized='view') }}

SELECT
  transaction_date AS date,
  transaction_amount AS amount,
  transaction_memo AS memo,
  account_key AS account_foreign_key,
  category_key AS category_foreign_key
FROM {{ ref('fct_transactions') }}
