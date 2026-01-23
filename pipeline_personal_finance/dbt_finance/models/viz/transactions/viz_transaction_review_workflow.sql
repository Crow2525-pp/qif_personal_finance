{{ config(materialized='view') }}

-- This view implements a comprehensive transaction review workflow with:
-- 1. Duplicate and reversal/chargeback detection
-- 2. Merchant grouping with trend sparkline and last purchase date
-- 3. Quick action fields for recategorize, mark transfer, and exclude from budget

WITH transaction_base AS (
  SELECT
    ft.transaction_key,
    ft.transaction_date,
    ft.account_key,
    da.account_name,
    da.bank_name,

    -- Amount fields
    ft.transaction_amount,
    ABS(ft.transaction_amount) AS amount_abs,
    ft.transaction_direction,

    -- Transaction details
    COALESCE(NULLIF(ft.transaction_memo, ''), ft.transaction_description) AS merchant,
    ft.transaction_memo,
    ft.transaction_description,
    ft.transaction_type,
    ft.location,

    -- Category
    dc.level_1_category,
    dc.level_2_subcategory,
    COALESCE(dc.is_income, FALSE) AS is_income,
    COALESCE(dc.is_internal_transfer, FALSE) AS is_internal_transfer,
    COALESCE(dc.is_financial_service, FALSE) AS is_financial_service,

    -- Metadata
    ft.etl_date,
    ft.fact_created_at

  FROM {{ ref('fct_transactions') }} ft
  LEFT JOIN {{ ref('dim_accounts') }} da ON ft.account_key = da.account_key
  LEFT JOIN {{ ref('dim_categories') }} dc ON ft.category_key = dc.category_key
  WHERE NOT COALESCE(ft.is_internal_transfer, FALSE)
    AND ft.transaction_date >= CURRENT_DATE - INTERVAL '12 months'
),

-- Detect duplicate transactions (same amount, merchant, and account within 24 hours)
duplicates AS (
  SELECT
    ft1.transaction_key AS transaction_key,
    COUNT(ft2.transaction_key) FILTER (
      WHERE ft2.transaction_date BETWEEN ft1.transaction_date - INTERVAL '1 day' AND ft1.transaction_date
        AND ft2.transaction_key != ft1.transaction_key
        AND ABS(ft2.transaction_amount) = ABS(ft1.transaction_amount)
        AND COALESCE(NULLIF(ft2.transaction_memo, ''), ft2.transaction_description) =
            COALESCE(NULLIF(ft1.transaction_memo, ''), ft1.transaction_description)
        AND ft2.account_key = ft1.account_key
    ) > 0 AS is_duplicate_flag,

    COUNT(ft2.transaction_key) FILTER (
      WHERE ft2.transaction_date BETWEEN ft1.transaction_date - INTERVAL '1 day' AND ft1.transaction_date
        AND ft2.transaction_key != ft1.transaction_key
        AND ABS(ft2.transaction_amount) = ABS(ft1.transaction_amount)
        AND COALESCE(NULLIF(ft2.transaction_memo, ''), ft2.transaction_description) =
            COALESCE(NULLIF(ft1.transaction_memo, ''), ft1.transaction_description)
        AND ft2.account_key = ft1.account_key
    ) AS duplicate_count

  FROM transaction_base ft1
  LEFT JOIN transaction_base ft2
    ON ft2.account_key = ft1.account_key
  GROUP BY ft1.transaction_key
),

-- Detect reversals and chargebacks (opposite amount to same merchant within 30 days)
reversals AS (
  SELECT
    ft1.transaction_key,
    COUNT(ft2.transaction_key) > 0 AS is_reversal_flag,
    STRING_AGG(
      DISTINCT CASE
        WHEN ft2.transaction_amount > 0 AND ft1.transaction_amount < 0 THEN 'REVERSAL'
        WHEN ft2.transaction_amount < 0 AND ft1.transaction_amount > 0 THEN 'CHARGEBACK'
        ELSE 'RELATED'
      END,
      ', ' ORDER BY
      CASE
        WHEN ft2.transaction_amount > 0 AND ft1.transaction_amount < 0 THEN 'REVERSAL'
        WHEN ft2.transaction_amount < 0 AND ft1.transaction_amount > 0 THEN 'CHARGEBACK'
        ELSE 'RELATED'
      END
    ) AS reversal_type

  FROM transaction_base ft1
  LEFT JOIN transaction_base ft2 ON
    ft2.transaction_date BETWEEN ft1.transaction_date - INTERVAL '30 days' AND ft1.transaction_date + INTERVAL '30 days'
    AND ft2.transaction_key != ft1.transaction_key
    AND ABS(ft2.transaction_amount) = ABS(ft1.transaction_amount)
    AND SIGN(ft2.transaction_amount) != SIGN(ft1.transaction_amount)
    AND COALESCE(NULLIF(ft2.transaction_memo, ''), ft2.transaction_description) =
        COALESCE(NULLIF(ft1.transaction_memo, ''), ft1.transaction_description)
    AND ft2.account_key = ft1.account_key
  GROUP BY ft1.transaction_key
),

-- Group transactions by merchant to calculate trends and last purchase date
merchant_monthly_spend AS (
  SELECT
    merchant,
    account_key,
    DATE_TRUNC('month', transaction_date) AS month_start,
    SUM(amount_abs) AS monthly_spend
  FROM transaction_base
  GROUP BY merchant, account_key, DATE_TRUNC('month', transaction_date)
),

merchant_trends AS (
  SELECT
    tb.merchant,
    tb.account_key,
    COUNT(*) AS merchant_transaction_count,
    SUM(amount_abs) AS merchant_total_spend,
    AVG(amount_abs) AS merchant_avg_spend,
    MAX(transaction_date) AS merchant_last_purchase_date,
    MIN(transaction_date) AS merchant_first_purchase_date,

    -- Calculate month-over-month trend (sparkline representation as text)
    STRING_AGG(
      TO_CHAR(mms.month_start, 'YYYY-MM') || ':' ||
      LPAD(ROUND(mms.monthly_spend)::text, 6, ' '),
      ' | ' ORDER BY mms.month_start
    ) AS merchant_trend_sparkline,

    -- Recent months trend for graphical representation
    ROUND(SUM(amount_abs) FILTER (WHERE transaction_date >= CURRENT_DATE - INTERVAL '1 month')::NUMERIC, 2) AS merchant_last_month,
    ROUND(SUM(amount_abs) FILTER (WHERE transaction_date >= CURRENT_DATE - INTERVAL '2 months'
                                    AND transaction_date < CURRENT_DATE - INTERVAL '1 month')::NUMERIC, 2) AS merchant_prev_month,

    -- Frequency analysis
    ROUND(
      (COUNT(*) * 30.0)
      / (NULLIF((MAX(transaction_date) - MIN(transaction_date))::numeric, 0) + 1),
      1
    ) AS merchant_frequency_per_month

  FROM transaction_base tb
  LEFT JOIN merchant_monthly_spend mms
    ON tb.merchant = mms.merchant
    AND tb.account_key = mms.account_key
  GROUP BY
    tb.merchant,
    tb.account_key
),

-- Combine all enrichments
enriched_transactions AS (
  SELECT
    tb.transaction_key,
    tb.transaction_date,
    tb.account_name,
    tb.bank_name,

    -- Amount
    tb.amount_abs,
    tb.transaction_amount,
    tb.transaction_direction,

    -- Merchant info
    tb.merchant,
    tb.transaction_description,
    tb.transaction_memo,

    -- Category
    tb.level_1_category,
    tb.level_2_subcategory,

    -- Flags
    COALESCE(dup.is_duplicate_flag, FALSE) AS is_duplicate,
    COALESCE(dup.duplicate_count, 0) AS duplicate_count,
    COALESCE(rev.is_reversal_flag, FALSE) AS is_reversal_or_chargeback,
    COALESCE(rev.reversal_type, '') AS reversal_type,

    -- Review status
    CASE
      WHEN COALESCE(dup.is_duplicate_flag, FALSE) THEN 'DUPLICATE'
      WHEN COALESCE(rev.is_reversal_flag, FALSE) THEN 'REVERSAL'
      WHEN tb.level_1_category = 'Uncategorized' THEN 'UNCATEGORIZED'
      WHEN ABS(tb.transaction_amount) > 500 THEN 'HIGH_VALUE'
      WHEN COALESCE(tb.is_financial_service, FALSE) THEN 'FINANCIAL_SERVICE'
      ELSE 'NORMAL'
    END AS review_status,

    -- Priority for review
    CASE
      WHEN COALESCE(dup.is_duplicate_flag, FALSE) THEN 1
      WHEN COALESCE(rev.is_reversal_flag, FALSE) THEN 2
      WHEN tb.level_1_category = 'Uncategorized' AND ABS(tb.transaction_amount) > 500 THEN 3
      WHEN tb.level_1_category = 'Uncategorized' THEN 4
      WHEN ABS(tb.transaction_amount) > 1000 THEN 5
      ELSE 99
    END AS review_priority,

    -- Merchant context from trends
    mt.merchant_transaction_count,
    mt.merchant_total_spend,
    mt.merchant_avg_spend,
    mt.merchant_last_purchase_date,
    mt.merchant_first_purchase_date,
    mt.merchant_trend_sparkline,
    mt.merchant_last_month,
    mt.merchant_prev_month,
    mt.merchant_frequency_per_month,

    -- Quick action URLs/guidance
    'RECATEGORIZE' AS quick_action_recategorize,
    'MARK_TRANSFER' AS quick_action_mark_transfer,
    'EXCLUDE_FROM_BUDGET' AS quick_action_exclude_budget,

    -- Helpful flags for quick actions
    CASE
      WHEN tb.transaction_amount > 0 AND NOT COALESCE(tb.is_income, FALSE) THEN TRUE
      ELSE FALSE
    END AS eligible_for_mark_transfer,

    CASE
      WHEN tb.level_1_category != 'Uncategorized' AND NOT COALESCE(tb.is_internal_transfer, FALSE) THEN TRUE
      ELSE FALSE
    END AS eligible_for_budget_exclusion,

    -- Metadata
    tb.transaction_type,
    tb.location,
    tb.etl_date,
    tb.fact_created_at

  FROM transaction_base tb
  LEFT JOIN duplicates dup ON tb.transaction_key = dup.transaction_key
  LEFT JOIN reversals rev ON tb.transaction_key = rev.transaction_key
  LEFT JOIN merchant_trends mt ON tb.merchant = mt.merchant AND tb.account_key = mt.account_key
)

SELECT *
FROM enriched_transactions
ORDER BY review_priority, transaction_date DESC
