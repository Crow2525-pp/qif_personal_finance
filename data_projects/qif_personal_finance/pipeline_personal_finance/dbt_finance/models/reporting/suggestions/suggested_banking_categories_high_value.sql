-- Suggested banking_categories rows for high-value uncategorized memos.
-- Copy desired rows into seeds/banking_categories.csv and adjust as needed.

WITH hvu AS (
  SELECT * FROM {{ ref('viz_high_value_uncategorized_by_period') }}
)

SELECT
  -- Columns aligned to seeds/banking_categories.csv
  hvu.sample_memo                                  AS transaction_description,
  CAST(NULL AS TEXT)                                AS transaction_type,
  CAST(NULL AS TEXT)                                AS sender,
  CAST(NULL AS TEXT)                                AS recipient,
  hvu.account_name                                  AS account_name,
  hvu.suggested_category                            AS category,
  hvu.suggested_subcategory                         AS subcategory,
  hvu.suggested_store                               AS store,
  COALESCE(hvu.suggested_internal_indicator, 'External') AS internal_indicator,

  -- Helpful extras for review (ignore when copying into CSV)
  hvu.period_type,
  hvu.period_start,
  hvu.memo_norm          AS normalized_memo,
  hvu.txn_count,
  hvu.total_amount_abs,
  hvu.support_count,
  hvu.total_support,
  hvu.confidence
FROM hvu
WHERE hvu.suggested_category IS NOT NULL
ORDER BY hvu.period_type, hvu.period_start, hvu.account_name, hvu.total_amount_abs DESC
