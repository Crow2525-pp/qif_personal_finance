{{ config(materialized='view') }}

-- This view is specifically designed to help identify and categorize uncategorized transactions
-- by showing the original memos alongside transaction details for manual categorization

WITH recent_uncategorized AS (
  SELECT
    ft.transaction_date,
    TO_CHAR(ft.transaction_date, 'YYYY-MM') AS year_month,
    TO_DATE(TO_CHAR(ft.transaction_date, 'YYYY-MM') || '-01', 'YYYY-MM-DD') AS month_start,

    ft.transaction_amount,
    ABS(ft.transaction_amount) AS amount_abs,

    -- Key fields for categorization - use description first, fall back to memo
    COALESCE(ft.transaction_description, ft.transaction_memo, 'NO_MEMO') AS original_memo,
    ft.transaction_memo AS standardized_memo,
    -- For analysis, use whichever has more content
    COALESCE(
      CASE WHEN LENGTH(TRIM(COALESCE(ft.transaction_description, ''))) > LENGTH(TRIM(COALESCE(ft.transaction_memo, '')))
           THEN ft.transaction_description
           ELSE ft.transaction_memo
      END,
      'NO_MEMO'
    ) AS best_memo,
    ft.transaction_type,
    ft.sender,
    ft.recipient,
    ft.location,

    -- Account context
    da.account_name,
    da.bank_name,
    da.account_type,

    -- Create a normalized version using the best available memo
    UPPER(
      REGEXP_REPLACE(
        REGEXP_REPLACE(
          REGEXP_REPLACE(
            REGEXP_REPLACE(
              COALESCE(
                CASE WHEN LENGTH(TRIM(COALESCE(ft.transaction_description, ''))) > LENGTH(TRIM(COALESCE(ft.transaction_memo, '')))
                     THEN ft.transaction_description
                     ELSE ft.transaction_memo
                END,
                ''
              ),
              'Receipt\\s+[0-9]+', ' ', 'gi'
            ),
            'Date\\s+\\d{2}\\s+[A-Za-z]{3}\\s+\\d{4}', ' ', 'gi'
          ),
          'Card\\s+[\\dx]+', ' ', 'gi'
        ),
        '[^A-Za-z0-9\\s]', ' ', 'g'
      )
    ) AS memo_normalized

  FROM {{ ref('fct_transactions') }} ft
  LEFT JOIN {{ ref('dim_accounts') }} da
    ON ft.account_key = da.account_key
  LEFT JOIN {{ ref('dim_categories') }} dc
    ON ft.category_key = dc.category_key

  WHERE dc.level_1_category = 'Uncategorized'
    AND ft.transaction_amount < 0  -- Only outflows (expenses)
    AND NOT COALESCE(ft.is_internal_transfer, FALSE)  -- Exclude internal transfers
    AND ft.transaction_date >= CURRENT_DATE - INTERVAL '3 months'  -- Last 3 months
    -- Include ALL uncategorized transactions, even those with empty memos
    -- AND COALESCE(ft.transaction_description, ft.transaction_memo) IS NOT NULL
    -- AND LENGTH(TRIM(COALESCE(ft.transaction_description, ft.transaction_memo))) > 2
),

-- Group by normalized memo and month to show patterns
monthly_patterns AS (
  SELECT
    year_month,
    month_start,
    memo_normalized,
    original_memo,
    standardized_memo,
    best_memo,
    account_name,
    bank_name,
    transaction_type,
    sender,
    recipient,

    -- Aggregated metrics
    COUNT(*) AS transaction_count,
    SUM(amount_abs) AS total_amount,
    AVG(amount_abs) AS avg_amount,
    MIN(amount_abs) AS min_amount,
    MAX(amount_abs) AS max_amount,

    -- Sample transaction for reference
    MIN(transaction_date) AS first_transaction_date,
    MAX(transaction_date) AS last_transaction_date,
    MIN(location) AS sample_location,

    -- List all individual transactions
    STRING_AGG(
      transaction_date::text || ': $' || amount_abs::text,
      '; ' ORDER BY transaction_date
    ) AS transaction_details

  FROM recent_uncategorized
  GROUP BY
    year_month,
    month_start,
    memo_normalized,
    original_memo,
    standardized_memo,
    best_memo,
    account_name,
    bank_name,
    transaction_type,
    sender,
    recipient
),

-- Add current month focus and priority ranking
with_priority AS (
  SELECT
    *,
    -- Is this from the current month?
    CASE WHEN month_start >= DATE_TRUNC('month', CURRENT_DATE) THEN 'CURRENT_MONTH' ELSE 'PREVIOUS_MONTH' END AS month_category,

    -- Priority for manual review
    CASE
      WHEN total_amount >= 1000 THEN 1
      WHEN total_amount >= 500 THEN 2
      WHEN total_amount >= 200 THEN 3
      WHEN total_amount >= 100 THEN 4
      ELSE 5
    END AS review_priority,

    -- Create suggested keywords for categorization help based on your CSV
    CASE
      -- Car & Transport (from your CSV)
      WHEN memo_normalized ILIKE '%SAWMAN%' OR memo_normalized ILIKE '%EXCEL%' OR memo_normalized ILIKE '%RACV%' THEN 'CAR_MAINTENANCE'
      WHEN memo_normalized ILIKE '%PETROLEUM%' OR memo_normalized ILIKE '%FUEL%' OR memo_normalized ILIKE '%BP%' OR memo_normalized ILIKE '%SHELL%' OR memo_normalized ILIKE '%AMPOL%' OR memo_normalized ILIKE '%CALTEX%' THEN 'FUEL'

      -- Health & Beauty (from your CSV)
      WHEN memo_normalized ILIKE '%MECCA%' OR memo_normalized ILIKE '%HAIR%' OR memo_normalized ILIKE '%BEAUTY%' THEN 'BEAUTY'
      WHEN memo_normalized ILIKE '%BODY FIT%' OR memo_normalized ILIKE '%GYM%' OR memo_normalized ILIKE '%FITNESS%' THEN 'FITNESS'
      WHEN memo_normalized ILIKE '%CHEMIST%' OR memo_normalized ILIKE '%PHARMACY%' THEN 'PHARMACY'

      -- Food & Dining (from your CSV and common patterns)
      WHEN memo_normalized ILIKE '%COLES%' OR memo_normalized ILIKE '%WOOLWORTH%' OR memo_normalized ILIKE '%ALDI%' THEN 'GROCERIES'
      WHEN memo_normalized ILIKE '%DREAM CAKE%' OR memo_normalized ILIKE '%CAKE%' OR memo_normalized ILIKE '%BAKERY%' THEN 'BAKERY_TREATS'
      WHEN memo_normalized ILIKE '%MCDONALD%' OR memo_normalized ILIKE '%CAFE%' OR memo_normalized ILIKE '%RESTAURANT%' OR memo_normalized ILIKE '%SUSHI%' OR memo_normalized ILIKE '%DELI%' OR memo_normalized ILIKE '%HOTEL%' THEN 'FOOD_DINING'
      WHEN memo_normalized ILIKE '%OTHER BROTHER%' OR memo_normalized ILIKE '%COFFEE%' THEN 'COFFEE'

      -- Shopping & Retail
      WHEN memo_normalized ILIKE '%BUNNINGS%' OR memo_normalized ILIKE '%HARDWARE%' THEN 'HOME_IMPROVEMENT'
      WHEN memo_normalized ILIKE '%AMAZON%' OR memo_normalized ILIKE '%EBAY%' THEN 'ONLINE_SHOPPING'
      WHEN memo_normalized ILIKE '%DREAM CARS%' THEN 'TOYS_HOBBIES'

      -- Professional Services
      WHEN memo_normalized ILIKE '%O RAFFERTY%' OR memo_normalized ILIKE '%RAFFERTY%' THEN 'PROFESSIONAL_SERVICES'

      -- Transfers & Payments
      WHEN memo_normalized ILIKE '%OSKO%' OR memo_normalized ILIKE '%PATTERSON%' OR memo_normalized ILIKE '%TRANSFER%' THEN 'INTERNAL_TRANSFER'
      WHEN memo_normalized ILIKE '%DIRECT DEBIT%' AND memo_normalized NOT ILIKE '%BODY FIT%' THEN 'UNIDENTIFIED_DIRECT_DEBIT'

      -- Utilities & Services
      WHEN memo_normalized ILIKE '%UTIL%' OR memo_normalized ILIKE '%ELECTRIC%' OR memo_normalized ILIKE '%GAS%' OR memo_normalized ILIKE '%WATER%' THEN 'UTILITIES'
      WHEN memo_normalized ILIKE '%NETFLIX%' OR memo_normalized ILIKE '%SPOTIFY%' OR memo_normalized ILIKE '%SUBSCRIPTION%' THEN 'SUBSCRIPTION'
      WHEN memo_normalized ILIKE '%INSURANCE%' THEN 'INSURANCE'

      ELSE 'NEEDS_MANUAL_REVIEW'
    END AS suggested_category_hint

  FROM monthly_patterns
)

SELECT
  year_month,
  month_category,
  review_priority,

  -- Original transaction info for categorization
  original_memo,
  standardized_memo,
  best_memo,
  memo_normalized,

  -- Transaction context
  account_name,
  bank_name,
  transaction_type,
  sender,
  recipient,
  sample_location,

  -- Financial impact
  total_amount,
  transaction_count,
  avg_amount,
  min_amount,
  max_amount,

  -- Timing (add timestamp for Grafana time series)
  month_start::timestamp AS time,
  first_transaction_date,
  last_transaction_date,
  transaction_details,

  -- Categorization help
  suggested_category_hint,

  -- Priority labels for dashboard
  CASE
    WHEN review_priority = 1 THEN '🔴 HIGH ($1000+)'
    WHEN review_priority = 2 THEN '🟠 MEDIUM ($500-$999)'
    WHEN review_priority = 3 THEN '🟡 MODERATE ($200-$499)'
    WHEN review_priority = 4 THEN '🟢 LOW ($100-$199)'
    ELSE '⚪ MINOR (<$100)'
  END AS priority_label

FROM with_priority
ORDER BY
  month_category ASC,  -- Current month first
  review_priority ASC, -- High priority first
  total_amount DESC    -- Largest amounts first within priority