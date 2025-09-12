-- High-confidence suggested rows for banking_categories.csv
-- Filters by confidence/support thresholds so you can copy with less review.

WITH hvu AS (
  SELECT * FROM {{ ref('viz_high_value_uncategorized_by_period') }}
),
params AS (
  SELECT 
    {{ var('suggestion_confidence_min', 0.6) }}::numeric AS confidence_min,
    {{ var('suggestion_support_min', 2) }}::int         AS support_min
)

SELECT DISTINCT
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

  -- Review metadata
  hvu.memo_norm          AS normalized_memo,
  hvu.txn_count,
  hvu.total_amount_abs,
  hvu.support_count,
  hvu.total_support,
  hvu.confidence
FROM hvu, params p
WHERE hvu.suggested_category IS NOT NULL
  AND hvu.support_count >= p.support_min
  AND hvu.confidence    >= p.confidence_min
ORDER BY hvu.account_name, hvu.total_amount_abs DESC
