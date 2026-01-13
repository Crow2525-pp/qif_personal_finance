{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['category_key'], 'unique': false},
      {'columns': ['category', 'subcategory'], 'unique': false}
    ]
  )
}}

WITH unique_categories AS (
  SELECT DISTINCT
    category,
    subcategory,
    store,
    internal_indicator
  FROM {{ ref('banking_categories') }}
),

category_hierarchy AS (
  SELECT
    {{ dbt_utils.generate_surrogate_key(['category', 'subcategory', 'store', 'internal_indicator']) }} AS category_key,

    -- Category hierarchy
    category AS level_1_category,
    subcategory AS level_2_subcategory,
    store AS level_3_store,

    -- Original fields for backward compatibility
    category,
    subcategory,
    store,
    internal_indicator,

    -- Enhanced categorization
    CASE
      WHEN internal_indicator = 'Internal' THEN 'Internal Transfer'
      WHEN category = 'Salary' THEN 'Income'
      WHEN category IN ('Mortgage', 'Bank Transaction') THEN 'Financial Services'
      WHEN category = 'Unclassified' THEN 'Uncategorized'
      ELSE 'Expense'
    END AS category_type,

    CASE
      WHEN internal_indicator = 'Internal' THEN TRUE
      ELSE FALSE
    END AS is_internal_transfer,

    CASE
      WHEN category = 'Salary' THEN TRUE
      ELSE FALSE
    END AS is_income,

    CASE
      WHEN category IN ('Mortgage', 'Bank Transaction') THEN TRUE
      ELSE FALSE
    END AS is_financial_service,

    -- Priority for categorization (lower number = higher priority)
    CAST(
        CASE
            WHEN internal_indicator = 'Internal' THEN 1
            WHEN category = 'Salary' THEN 2
            WHEN category = 'Mortgage' THEN 3
            WHEN category = 'Bank Transaction' THEN 4
            WHEN category = 'Unclassified' THEN 99
            ELSE 10
        END AS BIGINT
    ) AS category_priority,

    -- Description for reporting
    CASE
      WHEN internal_indicator = 'Internal' THEN 'Internal account transfers and adjustments'
      WHEN category = 'Salary' THEN 'Employment income and salary payments'
      WHEN category = 'Mortgage' THEN 'Home loan payments and fees'
      WHEN category = 'Bank Transaction' THEN 'General bank fees and transactions'
      WHEN category = 'Unclassified' THEN 'Transactions requiring manual categorization'
      ELSE 'General expenses and purchases'
    END AS category_description,

    -- Metadata
    CAST(CURRENT_TIMESTAMP AS TIMESTAMP) AS created_at,
    CAST(CURRENT_TIMESTAMP AS TIMESTAMP) AS updated_at

  FROM unique_categories
),

-- Add a default "Uncategorized" category for transactions without matches
default_category AS (
  SELECT
    MD5('Uncategorized' || 'Uncategorized' || 'Uncategorized' || 'External') AS category_key,
    'Uncategorized' AS level_1_category,
    'Uncategorized' AS level_2_subcategory,
    'Uncategorized' AS level_3_store,
    'Uncategorized' AS category,
    'Uncategorized' AS subcategory,
    'Uncategorized' AS store,
    'External' AS internal_indicator,
    'Uncategorized' AS category_type,
    FALSE AS is_internal_transfer,
    FALSE AS is_income,
    FALSE AS is_financial_service,
    CAST(999 AS BIGINT) AS category_priority,
    'Transactions that could not be automatically categorized' AS category_description,
    CAST(CURRENT_TIMESTAMP AS TIMESTAMP) AS created_at,
    CAST(CURRENT_TIMESTAMP AS TIMESTAMP) AS updated_at
  FROM (SELECT 1 AS dummy_col) -- Dummy table for single row
)

SELECT * FROM category_hierarchy
UNION ALL
SELECT * FROM default_category
