{{
  config(
    materialized='view'
  )
}}

WITH uncategorized_transactions AS (
  SELECT
    ft.transaction_date,
    ft.transaction_amount,
    ABS(ft.transaction_amount) AS amount_abs,

    -- Show both original fields for comparison
    ft.transaction_memo AS standardized_memo,  -- This is the standardized version
    ft.transaction_description AS original_description,  -- This might be more original

    -- Try to get the most original version available
    COALESCE(
      ft.transaction_description,  -- Try description first
      ft.transaction_memo         -- Fall back to memo
    ) AS original_memo,

    -- Account and classification info
    da.account_name,
    da.bank_name,
    ft.transaction_direction,

    -- Category info (should be Uncategorized)
    dc.level_1_category,
    dc.level_2_subcategory,

    -- Additional transaction details that might help with categorization
    ft.transaction_type,
    ft.sender,
    ft.recipient,
    ft.location

  FROM {{ ref('fct_transactions_enhanced') }} ft
  LEFT JOIN {{ ref('dim_accounts_enhanced') }} da
    ON ft.account_key = da.account_key
  LEFT JOIN {{ ref('dim_categories_enhanced') }} dc
    ON ft.category_key = dc.category_key

  WHERE dc.level_1_category = 'Uncategorized'
    AND ft.transaction_amount < 0  -- Only outflows (expenses)
    AND NOT COALESCE(ft.is_internal_transfer, FALSE)  -- Exclude internal transfers
    AND ft.transaction_date >= DATE_TRUNC('month', CURRENT_DATE - INTERVAL '1 month')  -- Last month
    AND COALESCE(ft.transaction_description, ft.transaction_memo) IS NOT NULL
    AND LENGTH(TRIM(COALESCE(ft.transaction_description, ft.transaction_memo))) > 1
),

-- Add some aggregation for similar transactions
uncategorized_grouped AS (
  SELECT
    original_memo,
    standardized_memo,
    account_name,
    bank_name,
    transaction_type,
    sender,
    recipient,

    -- Aggregated stats
    COUNT(*) AS transaction_count,
    SUM(amount_abs) AS total_amount,
    AVG(amount_abs) AS avg_amount,
    MIN(transaction_date) AS first_transaction_date,
    MAX(transaction_date) AS last_transaction_date,

    -- Sample values for reference
    MIN(location) AS sample_location,

    -- Show all individual amounts for manual review
    STRING_AGG(amount_abs::text, ', ' ORDER BY transaction_date) AS all_amounts,
    STRING_AGG(transaction_date::text, ', ' ORDER BY transaction_date) AS all_dates

  FROM uncategorized_transactions
  GROUP BY
    original_memo,
    standardized_memo,
    account_name,
    bank_name,
    transaction_type,
    sender,
    recipient
)

SELECT
  -- Original memo for categorization
  original_memo,
  standardized_memo,

  -- Account context
  account_name,
  bank_name,

  -- Transaction details that help with categorization
  transaction_type,
  sender,
  recipient,
  sample_location,

  -- Financial impact
  total_amount,
  transaction_count,
  avg_amount,

  -- Timing info
  first_transaction_date,
  last_transaction_date,

  -- Detailed transaction info for review
  all_amounts,
  all_dates,

  -- Flag high-value items that need urgent attention
  CASE
    WHEN total_amount >= 1000 THEN 'HIGH'
    WHEN total_amount >= 500 THEN 'MEDIUM'
    WHEN total_amount >= 100 THEN 'LOW'
    ELSE 'MINOR'
  END AS priority_level

FROM uncategorized_grouped
ORDER BY total_amount DESC, transaction_count DESC