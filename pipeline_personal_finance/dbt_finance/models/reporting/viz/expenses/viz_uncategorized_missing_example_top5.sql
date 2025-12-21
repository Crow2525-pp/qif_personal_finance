-- Top 5 high-value uncategorized groups that still lack an example transaction text
-- This complements viz_high_value_uncategorized_by_period by highlighting gaps
-- in sample/example extraction for the dashboard.

WITH params AS (
    SELECT
        -- How many months back to consider
        COALESCE({{ var('uncat_missing_example_months', 12) }}, 12)::int AS months_back
),

base AS (
    SELECT
        hvu.period_start::date                 AS period_start,
        TO_CHAR(hvu.period_start, 'YYYY-MM')   AS month,
        hvu.account_name,
        hvu.memo_norm,
        hvu.sample_memo                        AS example_transaction,
        hvu.txn_count                          AS count,
        hvu.total_amount_abs                   AS amount,
        hvu.suggested_category,
        hvu.suggested_subcategory,
        hvu.confidence
    FROM {{ ref('viz_high_value_uncategorized_by_period') }} hvu
    WHERE hvu.period_type = 'month'
      AND hvu.period_start >= (DATE_TRUNC('month', CURRENT_DATE) - (
            (SELECT months_back FROM params) || ' months'
        )::interval)
),

missing_example AS (
    SELECT *
    FROM base
    WHERE example_transaction IS NULL OR LENGTH(TRIM(example_transaction)) = 0
),

ranked AS (
    SELECT
        me.*,
        ROW_NUMBER() OVER (
            ORDER BY me.amount DESC, me.period_start DESC, me.account_name
        ) AS rnk
    FROM missing_example me
)

SELECT
    month,
    account_name,
    amount,
    count,
    example_transaction,
    suggested_category,
    suggested_subcategory,
    confidence
FROM ranked
WHERE rnk <= 5
ORDER BY rnk

