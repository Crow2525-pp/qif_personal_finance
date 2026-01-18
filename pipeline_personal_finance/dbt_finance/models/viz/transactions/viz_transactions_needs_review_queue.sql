{{ config(materialized='view') }}

-- This view creates a 'needs review' queue combining:
-- 1. Large transactions (>$500)
-- 2. Uncategorized transactions
-- 3. Transactions from new merchants (first occurrence)

WITH transaction_context AS (
  SELECT
    ft.transaction_date,
    TO_CHAR(ft.transaction_date, 'YYYY-MM') AS year_month,
    ft.transaction_amount,
    ABS(ft.transaction_amount) AS amount_abs,

    -- Account context
    da.account_name,
    da.bank_name,
    da.account_type,

    -- Merchant/Category context
    COALESCE(dc.store, 'Unknown') AS merchant_name,
    dc.category AS category_name,
    dc.level_1_category,
    dc.level_2_subcategory,

    -- Transaction details
    ft.transaction_memo,
    ft.transaction_description,
    ft.transaction_type,
    ft.sender,
    ft.recipient,
    ft.location,

    -- Flags
    ft.is_income_transaction,
    ft.is_internal_transfer,
    ft.is_financial_service,

    -- First occurrence of merchant
    MIN(ft.transaction_date) OVER (
      PARTITION BY UPPER(COALESCE(dc.store, ft.transaction_memo))
    ) AS merchant_first_seen,

    -- Count transactions with this merchant in past 12 months (time-based)
    COUNT(*) OVER (
      PARTITION BY UPPER(COALESCE(dc.store, ft.transaction_memo))
      ORDER BY ft.transaction_date
      RANGE BETWEEN INTERVAL '12 months' PRECEDING AND CURRENT ROW
    ) AS merchant_12m_transaction_count

  FROM {{ ref('fct_transactions') }} ft
  LEFT JOIN {{ ref('dim_accounts') }} da
    ON ft.account_key = da.account_key
  LEFT JOIN {{ ref('dim_categories') }} dc
    ON ft.category_key = dc.category_key

  WHERE ft.transaction_amount < 0  -- Only expenses
    AND NOT COALESCE(ft.is_internal_transfer, FALSE)  -- Exclude internal transfers
    AND NOT COALESCE(ft.is_financial_service, FALSE)  -- Exclude financial services
),

-- Identify which category each transaction falls into for review
with_review_reasons AS (
  SELECT
    *,

    -- Determine review reasons
    CASE
      WHEN amount_abs >= 500 THEN 'LARGE_TRANSACTION'
      WHEN level_1_category = 'Uncategorized' THEN 'UNCATEGORIZED'
      WHEN merchant_12m_transaction_count = 1 AND transaction_date >= CURRENT_DATE - INTERVAL '30 days' THEN 'NEW_MERCHANT'
      ELSE NULL
    END AS primary_review_reason,

    -- Secondary reason: new merchant (appeared for first time)
    CASE
      WHEN transaction_date = merchant_first_seen AND merchant_12m_transaction_count = 1 THEN TRUE
      ELSE FALSE
    END AS is_new_merchant,

    -- Days since first occurrence of merchant
    CAST(CURRENT_DATE - merchant_first_seen AS INTEGER) AS days_since_merchant_first_seen

  FROM transaction_context
),

review_priority_ranked AS (
  SELECT
    *,
    -- Review priority (1 = highest)
    CASE
      WHEN amount_abs >= 1000 AND level_1_category = 'Uncategorized' THEN 1  -- Large + uncategorized
      WHEN amount_abs >= 1000 THEN 2  -- Large transactions
      WHEN level_1_category = 'Uncategorized' AND amount_abs >= 100 THEN 3  -- Uncategorized >$100
      WHEN is_new_merchant AND amount_abs >= 200 THEN 4  -- New merchant >$200
      WHEN level_1_category = 'Uncategorized' THEN 5  -- Any uncategorized
      WHEN amount_abs >= 500 THEN 6  -- Large but categorized
      WHEN is_new_merchant THEN 7  -- New merchant (any amount)
      ELSE NULL
    END AS review_priority
  FROM with_review_reasons
)

SELECT
  transaction_date,
  year_month,
  TO_DATE(year_month || '-01', 'YYYY-MM-DD')::timestamp AS time,

  -- Transaction amount
  transaction_amount,
  amount_abs,

  -- Account context
  account_name,
  bank_name,
  account_type,

  -- Merchant/Category context
  merchant_name,
  category_name,
  level_1_category,
  level_2_subcategory,

  -- Transaction details
  transaction_memo,
  transaction_description,
  transaction_type,
  sender,
  recipient,
  location,

  -- Review reason
  primary_review_reason,
  is_new_merchant,
  merchant_12m_transaction_count,
  days_since_merchant_first_seen,

  -- Review priority
  review_priority,

  -- Priority label for dashboard
  CASE
    WHEN review_priority = 1 THEN '🔴 CRITICAL - Large Uncategorized'
    WHEN review_priority = 2 THEN '🟠 HIGH - Large Transaction'
    WHEN review_priority = 3 THEN '🟡 MEDIUM - Uncategorized >$100'
    WHEN review_priority = 4 THEN '🔵 MEDIUM - New Merchant >$200'
    WHEN review_priority = 5 THEN '🟢 LOW - Uncategorized <$100'
    WHEN review_priority = 6 THEN '⚪ LOW - Large Categorized'
    WHEN review_priority = 7 THEN '⚪ LOW - New Merchant'
    ELSE 'Not for review'
  END AS priority_label,

  -- Status flags
  CASE
    WHEN review_priority IS NOT NULL AND transaction_date >= CURRENT_DATE - INTERVAL '7 days' THEN 'RECENT'
    WHEN review_priority IS NOT NULL AND transaction_date >= CURRENT_DATE - INTERVAL '30 days' THEN 'CURRENT_MONTH'
    WHEN review_priority IS NOT NULL THEN 'OLDER'
    ELSE 'NOT_IN_QUEUE'
  END AS queue_status

FROM review_priority_ranked

WHERE review_priority IS NOT NULL  -- Only return transactions that need review
  OR transaction_date >= CURRENT_DATE - INTERVAL '3 months'  -- Or show recent context

ORDER BY
  review_priority ASC,
  amount_abs DESC,
  transaction_date DESC
