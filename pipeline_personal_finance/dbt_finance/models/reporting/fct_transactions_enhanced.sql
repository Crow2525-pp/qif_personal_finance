{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['transaction_date'], 'unique': false},
      {'columns': ['account_key'], 'unique': false}, 
      {'columns': ['category_key'], 'unique': false},
      {'columns': ['transaction_key'], 'unique': false}
    ],
    post_hook=[
      "{{ create_fk_if_not_exists(this, 'account_key', ref('dim_accounts_enhanced'), 'account_key', 'fk_fct_txn_account') }}",
      "{{ create_fk_if_not_exists(this, 'category_key', ref('dim_categories_enhanced'), 'category_key', 'fk_fct_txn_category') }}"
    ]
  )
}}

WITH categorized_transactions AS (
  SELECT * FROM {{ ref('int_categories') }}
),

-- Deduplicate in case there are duplicate primary_keys
deduplicated_transactions AS (
  SELECT DISTINCT * FROM categorized_transactions
),

fact_base AS (
  SELECT
    -- Surrogate key
    {{ dbt_utils.generate_surrogate_key(['ct.primary_key']) }} AS transaction_key,
    
    -- Natural key
    ct.primary_key AS transaction_natural_key,
    
    -- Date dimension
    ct.transaction_date,
    CAST(EXTRACT(YEAR FROM ct.transaction_date) AS BIGINT) AS transaction_year,
    CAST(EXTRACT(QUARTER FROM ct.transaction_date) AS BIGINT) AS transaction_quarter,
    CAST(EXTRACT(MONTH FROM ct.transaction_date) AS BIGINT) AS transaction_month,
    CAST(EXTRACT(DAY FROM ct.transaction_date) AS BIGINT) AS transaction_day,
    CAST(EXTRACT(DOW FROM ct.transaction_date) AS BIGINT) AS day_of_week,
    
    -- Foreign keys
    da.account_key,
    COALESCE(dc.category_key, 
      MD5('Uncategorized' || 'Uncategorized' || 'Uncategorized' || 'External')
    ) AS category_key,
    
    -- Transaction measures  
    ROUND(ct.transaction_amount::NUMERIC, 2) AS transaction_amount,
    ROUND(ct.adjusted_transaction_balance::NUMERIC, 2) AS account_balance,
    
    -- Transaction attributes
    CASE
      WHEN ct.transaction_amount > 0 THEN 'Debit'
      WHEN ct.transaction_amount < 0 THEN 'Credit' 
      ELSE 'Zero'
    END AS transaction_direction,
    
    ABS(ROUND(ct.transaction_amount::NUMERIC, 2)) AS transaction_amount_abs,
    
    -- Categorization flags
    COALESCE(dc.is_income, FALSE) AS is_income_transaction,
    COALESCE(dc.is_internal_transfer, FALSE) AS is_internal_transfer,
    COALESCE(dc.is_financial_service, FALSE) AS is_financial_service,
    
    -- Transaction details
    ct.memo AS transaction_memo,
    ct.transaction_type,
    ct.transaction_description,
    ct.receipt,
    ct.location,
    ct.sender,
    ct.recipient,
    
    -- ETL metadata
    CAST(ct.etl_date AS TEXT) AS etl_date,
    CAST(ct.etl_time AS TEXT) AS etl_time,
    CAST(CURRENT_TIMESTAMP AS TIMESTAMP) AS fact_created_at
    
  FROM deduplicated_transactions ct
  LEFT JOIN {{ ref('dim_accounts_enhanced') }} da
    ON ct.account_name = da.account_name
  LEFT JOIN {{ ref('dim_categories_enhanced') }} dc  
    ON ct.category_foreign_key = dc.category_key
)

SELECT * FROM fact_base
