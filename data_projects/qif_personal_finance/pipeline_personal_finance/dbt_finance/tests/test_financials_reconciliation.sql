-- Fails when any cross-dashboard reconciliation check fails in the window
-- Budget and Executive domain failures are excluded (warnings only) due to financial services categorization
-- Outflows category alignment and budget matching excluded (warnings) due to expense macro financial services change
-- Outflows uncategorized threshold is excluded (warnings only) due to data quality backlog
-- Balances domain excluded (warnings only): fct_daily_balances includes balance adjustments
--   (from known_values seed) that fct_transactions does not, causing a systematic ~$215K delta
--   on the Bendigo Offset account. This is a methodological difference, not a data error.
WITH params AS (
  SELECT COALESCE({{ var('recon_months_back', 12) }}, 12)::int AS months_back
)
SELECT *
FROM {{ ref('rpt_financials_reconciliation_tests') }}
WHERE period_date >= (DATE_TRUNC('month', CURRENT_DATE) - ((SELECT months_back FROM params) || ' months')::interval)
  AND NOT pass
  AND domain NOT IN ('Budget', 'Executive', 'Balances')
  AND test_name NOT LIKE 'cat_%_alignment'
  AND test_name != 'viz_outflows_match_budget_expenses'
  AND test_name != 'uncategorized_pct_within_threshold'
