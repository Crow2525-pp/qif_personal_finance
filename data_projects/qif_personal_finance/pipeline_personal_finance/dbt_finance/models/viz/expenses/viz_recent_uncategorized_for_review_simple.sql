{{
  config(
    materialized='view'
  )
}}

-- Simple view to show ALL uncategorized transactions with original memos for categorization

SELECT
  ft.transaction_date,
  TO_CHAR(ft.transaction_date, 'YYYY-MM') AS year_month,
  CASE
    WHEN ft.transaction_date >= DATE_TRUNC('month', CURRENT_DATE) THEN 'CURRENT_MONTH'
    ELSE 'PREVIOUS_MONTH'
  END AS month_category,

  -- Financial details
  ABS(ft.transaction_amount) AS amount,
  CASE
    WHEN ABS(ft.transaction_amount) >= 1000 THEN 1
    WHEN ABS(ft.transaction_amount) >= 500 THEN 2
    WHEN ABS(ft.transaction_amount) >= 200 THEN 3
    WHEN ABS(ft.transaction_amount) >= 100 THEN 4
    ELSE 5
  END AS review_priority,

  CASE
    WHEN ABS(ft.transaction_amount) >= 1000 THEN '🔴 HIGH ($1000+)'
    WHEN ABS(ft.transaction_amount) >= 500 THEN '🟠 MEDIUM ($500-$999)'
    WHEN ABS(ft.transaction_amount) >= 200 THEN '🟡 MODERATE ($200-$499)'
    WHEN ABS(ft.transaction_amount) >= 100 THEN '🟢 LOW ($100-$199)'
    ELSE '⚪ MINOR (<$100)'
  END AS priority_label,

  -- Memo information for categorization
  COALESCE(ft.transaction_description, ft.transaction_memo, 'NO_MEMO') AS original_memo,
  ft.transaction_memo AS standardized_memo,

  -- Use the longer/more detailed memo for analysis
  CASE
    WHEN LENGTH(TRIM(COALESCE(ft.transaction_description, ''))) > LENGTH(TRIM(COALESCE(ft.transaction_memo, '')))
    THEN ft.transaction_description
    ELSE ft.transaction_memo
  END AS best_memo,

  -- Account context
  da.account_name,
  da.bank_name,

  -- Additional transaction details
  ft.transaction_type,
  ft.sender,
  ft.recipient,
  ft.location,

  -- Categorization hints based on memo content
  CASE
    -- Car & Transport (from your CSV)
    WHEN ft.transaction_memo ILIKE '%SAWMAN%' OR ft.transaction_memo ILIKE '%EXCEL%' OR ft.transaction_memo ILIKE '%RACV%' THEN 'CAR_MAINTENANCE'
    WHEN ft.transaction_memo ILIKE '%PETROLEUM%' OR ft.transaction_memo ILIKE '%FUEL%' OR ft.transaction_memo ILIKE '%BP%' OR ft.transaction_memo ILIKE '%SHELL%' OR ft.transaction_memo ILIKE '%AMPOL%' OR ft.transaction_memo ILIKE '%CALTEX%' THEN 'FUEL'

    -- Health & Beauty (from your CSV)
    WHEN ft.transaction_memo ILIKE '%MECCA%' OR ft.transaction_memo ILIKE '%HAIR%' OR ft.transaction_memo ILIKE '%BEAUTY%' THEN 'BEAUTY'
    WHEN ft.transaction_memo ILIKE '%BODY FIT%' OR ft.transaction_memo ILIKE '%GYM%' OR ft.transaction_memo ILIKE '%FITNESS%' THEN 'FITNESS'
    WHEN ft.transaction_memo ILIKE '%CHEMIST%' OR ft.transaction_memo ILIKE '%PHARMACY%' THEN 'PHARMACY'

    -- Food & Dining (from your CSV and common patterns)
    WHEN ft.transaction_memo ILIKE '%COLES%' OR ft.transaction_memo ILIKE '%WOOLWORTH%' OR ft.transaction_memo ILIKE '%ALDI%' THEN 'GROCERIES'
    WHEN ft.transaction_memo ILIKE '%DREAM CAKE%' OR ft.transaction_memo ILIKE '%CAKE%' OR ft.transaction_memo ILIKE '%BAKERY%' THEN 'BAKERY_TREATS'
    WHEN ft.transaction_memo ILIKE '%MCDONALD%' OR ft.transaction_memo ILIKE '%CAFE%' OR ft.transaction_memo ILIKE '%RESTAURANT%' OR ft.transaction_memo ILIKE '%SUSHI%' OR ft.transaction_memo ILIKE '%DELI%' OR ft.transaction_memo ILIKE '%HOTEL%' THEN 'FOOD_DINING'
    WHEN ft.transaction_memo ILIKE '%OTHER BROTHER%' OR ft.transaction_memo ILIKE '%COFFEE%' THEN 'COFFEE'

    -- Shopping & Retail
    WHEN ft.transaction_memo ILIKE '%BUNNINGS%' OR ft.transaction_memo ILIKE '%HARDWARE%' THEN 'HOME_IMPROVEMENT'
    WHEN ft.transaction_memo ILIKE '%AMAZON%' OR ft.transaction_memo ILIKE '%EBAY%' THEN 'ONLINE_SHOPPING'
    WHEN ft.transaction_memo ILIKE '%DREAM CARS%' THEN 'TOYS_HOBBIES'

    -- Professional Services
    WHEN ft.transaction_memo ILIKE '%O RAFFERTY%' OR ft.transaction_memo ILIKE '%RAFFERTY%' THEN 'PROFESSIONAL_SERVICES'

    -- Transfers & Payments
    WHEN ft.transaction_memo ILIKE '%OSKO%' OR ft.transaction_memo ILIKE '%PATTERSON%' OR ft.transaction_memo ILIKE '%TRANSFER%' THEN 'INTERNAL_TRANSFER'
    WHEN ft.transaction_memo ILIKE '%DIRECT DEBIT%' AND ft.transaction_memo NOT ILIKE '%BODY FIT%' THEN 'UNIDENTIFIED_DIRECT_DEBIT'

    -- Utilities & Services
    WHEN ft.transaction_memo ILIKE '%UTIL%' OR ft.transaction_memo ILIKE '%ELECTRIC%' OR ft.transaction_memo ILIKE '%GAS%' OR ft.transaction_memo ILIKE '%WATER%' THEN 'UTILITIES'
    WHEN ft.transaction_memo ILIKE '%NETFLIX%' OR ft.transaction_memo ILIKE '%SPOTIFY%' OR ft.transaction_memo ILIKE '%SUBSCRIPTION%' THEN 'SUBSCRIPTION'
    WHEN ft.transaction_memo ILIKE '%INSURANCE%' THEN 'INSURANCE'

    ELSE 'NEEDS_MANUAL_REVIEW'
  END AS suggested_category_hint

FROM {{ ref('fct_transactions') }} ft
LEFT JOIN {{ ref('dim_accounts') }} da
  ON ft.account_key = da.account_key
LEFT JOIN {{ ref('dim_categories') }} dc
  ON ft.category_key = dc.category_key

WHERE dc.level_1_category = 'Uncategorized'
  AND ft.transaction_amount < 0  -- Only outflows (expenses)
  AND NOT COALESCE(ft.is_internal_transfer, FALSE)  -- Exclude internal transfers
  AND ft.transaction_date >= CURRENT_DATE - INTERVAL '3 months'  -- Last 3 months

ORDER BY
  month_category ASC,    -- Current month first
  review_priority ASC,   -- High priority first
  ABS(ft.transaction_amount) DESC  -- Largest amounts first