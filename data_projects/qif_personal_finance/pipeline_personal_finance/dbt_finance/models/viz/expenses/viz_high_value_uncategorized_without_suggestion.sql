-- High-value uncategorized groups that still lack any suggestion.

WITH hvu AS (
  SELECT * FROM {{ ref('viz_high_value_uncategorized_by_period') }}
)

SELECT 
  hvu.period_type,
  hvu.period_start,
  hvu.account_name,
  hvu.memo_norm,
  hvu.sample_memo,
  hvu.txn_count,
  hvu.total_amount_abs
FROM hvu
WHERE hvu.suggested_category IS NULL
ORDER BY hvu.period_type, hvu.period_start, hvu.account_name, hvu.total_amount_abs DESC
