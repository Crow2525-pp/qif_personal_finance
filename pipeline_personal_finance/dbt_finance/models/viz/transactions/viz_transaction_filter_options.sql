{{ config(materialized='view') }}

-- This view provides distinct filter options for dashboards:
-- - Account names and details
-- - Merchant names (stores)
-- - Category names (with hierarchy)
-- Used for populating dropdown filters in Transaction Analysis dashboard

WITH account_filters AS (
  SELECT DISTINCT
    'account' AS filter_type,
    da.account_name AS filter_value,
    da.bank_name AS filter_group,
    COUNT(DISTINCT ft.transaction_key) OVER (PARTITION BY da.account_key) AS transaction_count,
    da.account_type AS filter_detail

  FROM {{ ref('fct_transactions') }} ft
  LEFT JOIN {{ ref('dim_accounts') }} da
    ON ft.account_key = da.account_key

  WHERE ft.transaction_amount < 0  -- Only expenses for filtering
    AND NOT COALESCE(ft.is_internal_transfer, FALSE)
    AND da.account_name IS NOT NULL
),

merchant_filters AS (
  SELECT DISTINCT
    'merchant' AS filter_type,
    COALESCE(dc.store, 'Unknown Merchant') AS filter_value,
    dc.level_1_category AS filter_group,
    COUNT(DISTINCT ft.transaction_key) OVER (
      PARTITION BY UPPER(COALESCE(dc.store, ft.transaction_memo))
    ) AS transaction_count,
    dc.level_2_subcategory AS filter_detail

  FROM {{ ref('fct_transactions') }} ft
  LEFT JOIN {{ ref('dim_categories') }} dc
    ON ft.category_key = dc.category_key

  WHERE ft.transaction_amount < 0  -- Only expenses for filtering
    AND NOT COALESCE(ft.is_internal_transfer, FALSE)
    AND COALESCE(dc.store, 'Unknown') IS NOT NULL
),

category_filters AS (
  SELECT DISTINCT
    'category' AS filter_type,
    dc.category AS filter_value,
    dc.level_1_category AS filter_group,
    COUNT(DISTINCT ft.transaction_key) OVER (PARTITION BY dc.category_key) AS transaction_count,
    dc.level_2_subcategory AS filter_detail

  FROM {{ ref('fct_transactions') }} ft
  LEFT JOIN {{ ref('dim_categories') }} dc
    ON ft.category_key = dc.category_key

  WHERE ft.transaction_amount < 0  -- Only expenses for filtering
    AND NOT COALESCE(ft.is_internal_transfer, FALSE)
    AND dc.category IS NOT NULL
)

SELECT
  filter_type,
  filter_value,
  filter_group,
  transaction_count,
  filter_detail,
  ROW_NUMBER() OVER (PARTITION BY filter_type ORDER BY transaction_count DESC) AS filter_rank

FROM (
  SELECT * FROM account_filters
  UNION ALL
  SELECT * FROM merchant_filters
  UNION ALL
  SELECT * FROM category_filters
)

ORDER BY
  filter_type ASC,
  transaction_count DESC,
  filter_value ASC
