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

known_flags AS (
  SELECT DISTINCT
    LOWER(account_name) AS account_name_lower,
    -- Robust boolean parsing from seed CSV strings (handle empty strings and nulls)
    CASE WHEN LOWER(TRIM(COALESCE(is_asset::text, 'false'))) IN ('true','t','1','yes','y') THEN TRUE ELSE FALSE END       AS is_asset,
    CASE WHEN LOWER(TRIM(COALESCE(is_liquid_asset::text, 'false'))) IN ('true','t','1','yes','y') THEN TRUE ELSE FALSE END AS is_liquid_asset,
    CASE WHEN LOWER(TRIM(COALESCE(is_loan::text, 'false'))) IN ('true','t','1','yes','y') THEN TRUE ELSE FALSE END         AS is_loan,
    CASE WHEN LOWER(TRIM(COALESCE(is_homeloan::text, 'false'))) IN ('true','t','1','yes','y') THEN TRUE ELSE FALSE END     AS is_homeloan,
    CASE WHEN LOWER(TRIM(COALESCE(is_debt::text, 'false'))) IN ('true','t','1','yes','y') THEN TRUE ELSE FALSE END         AS is_debt
  FROM {{ ref('known_values') }}
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

    -- Business logic flags (prefer seed flags; fall back to heuristics)
    COALESCE(k.is_loan OR k.is_debt,
             CASE WHEN account_category = 'Liability' THEN TRUE ELSE FALSE END) AS is_liability,
    CASE WHEN account_type IN ('Offset', 'Bills Account', 'Everyday Account') THEN TRUE ELSE FALSE END AS is_transactional,
    COALESCE(k.is_homeloan,
             CASE WHEN account_type = 'Home Loan' THEN TRUE ELSE FALSE END) AS is_mortgage,
    -- Expose additional flags from seeds for downstream use
    COALESCE(k.is_asset, CASE WHEN account_category = 'Asset' THEN TRUE ELSE FALSE END)       AS is_asset,
    COALESCE(k.is_liquid_asset, CASE WHEN account_type IN ('Offset','Bills Account','Everyday Account') THEN TRUE ELSE FALSE END) AS is_liquid_asset,

    -- Metadata
    CAST(CURRENT_TIMESTAMP AS TIMESTAMP) AS created_at,
    CAST(CURRENT_TIMESTAMP AS TIMESTAMP) AS updated_at

  FROM account_metadata am
  LEFT JOIN known_flags k
    ON LOWER(am.account_name) = k.account_name_lower
)

SELECT * FROM account_hierarchy
