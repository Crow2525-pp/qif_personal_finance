{{
  config(
    materialized='table',
    contract={'enforced': true},
    indexes=[
      {'columns': ['account_key'], 'unique': true},
      {'columns': ['bank_name', 'account_type'], 'unique': false}
    ]
  )
}}

{#- Define the model contract -#}
{% set model_contract = [
  {'name': 'account_key', 'data_type': 'text'},
  {'name': 'account_name', 'data_type': 'text'},
  {'name': 'bank_name', 'data_type': 'text'},
  {'name': 'account_type', 'data_type': 'text'},
  {'name': 'account_category', 'data_type': 'text'},
  {'name': 'level_1_bank', 'data_type': 'text'},
  {'name': 'level_2_category', 'data_type': 'text'},
  {'name': 'level_3_type', 'data_type': 'text'},
  {'name': 'level_4_account', 'data_type': 'text'},
  {'name': 'account_start_date', 'data_type': 'date'},
  {'name': 'account_last_transaction_date', 'data_type': 'date'},
  {'name': 'total_transactions', 'data_type': 'bigint'},
  {'name': 'currency_code', 'data_type': 'text'},
  {'name': 'is_active', 'data_type': 'boolean'},
  {'name': 'is_liability', 'data_type': 'boolean'},
  {'name': 'is_transactional', 'data_type': 'boolean'},
  {'name': 'is_mortgage', 'data_type': 'boolean'},
  {'name': 'created_at', 'data_type': 'timestamp'},
  {'name': 'updated_at', 'data_type': 'timestamp'}
] %}

WITH account_metadata AS (
  SELECT DISTINCT
    account_name,
    CASE 
      WHEN account_name LIKE '%adelaide%' THEN 'Adelaide Bank'
      WHEN account_name LIKE '%bendigo%' THEN 'Bendigo Bank' 
      WHEN account_name LIKE '%ing%' THEN 'ING Australia'
      ELSE 'Unknown'
    END AS bank_name,
    
    CASE
      WHEN account_name LIKE '%homeloan%' THEN 'Home Loan'
      WHEN account_name LIKE '%offset%' THEN 'Offset'
      WHEN account_name LIKE '%billsbillsbills%' THEN 'Bills Account'
      WHEN account_name LIKE '%countdown%' THEN 'Everyday Account'
      ELSE 'Unknown'
    END AS account_type,
    
    CASE
      WHEN account_name LIKE '%homeloan%' THEN 'Liability'
      WHEN account_name LIKE '%offset%' THEN 'Asset'
      WHEN account_name LIKE '%billsbillsbills%' THEN 'Asset'
      WHEN account_name LIKE '%countdown%' THEN 'Asset'
      ELSE 'Unknown'
    END AS account_category,
    
    MIN(transaction_date) AS account_start_date,
    MAX(transaction_date) AS account_last_transaction_date,
    COUNT(*) AS total_transactions,
    'AUD' AS currency_code,
    TRUE AS is_active
    
  FROM {{ ref('int_account_balances') }}
  GROUP BY account_name
),

account_hierarchy AS (
  SELECT 
    {{ dbt_utils.generate_surrogate_key(['account_name']) }} AS account_key,
    account_name AS account_name,
    bank_name,
    account_type,
    account_category,
    
    -- Create hierarchy levels
    bank_name AS level_1_bank,
    account_category AS level_2_category,  
    account_type AS level_3_type,
    account_name AS level_4_account,
    
    -- Account attributes
    account_start_date,
    account_last_transaction_date,
    total_transactions,
    currency_code,
    is_active,
    
    -- Business logic flags
    CASE WHEN account_category = 'Liability' THEN TRUE ELSE FALSE END AS is_liability,
    CASE WHEN account_type IN ('Offset', 'Bills Account', 'Everyday Account') THEN TRUE ELSE FALSE END AS is_transactional,
    CASE WHEN account_type = 'Home Loan' THEN TRUE ELSE FALSE END AS is_mortgage,
    
    -- Metadata
    CURRENT_TIMESTAMP AS created_at,
    CURRENT_TIMESTAMP AS updated_at
    
  FROM account_metadata
)

SELECT * FROM account_hierarchy