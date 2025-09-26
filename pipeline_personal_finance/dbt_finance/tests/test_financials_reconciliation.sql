-- Fails when any cross-dashboard reconciliation check fails in the window
WITH params AS (
  SELECT COALESCE({{ var('recon_months_back', 12) }}, 12)::int AS months_back
)
SELECT *
FROM {{ ref('rpt_financials_reconciliation_tests') }}
WHERE period_date >= (DATE_TRUNC('month', CURRENT_DATE) - ((SELECT months_back FROM params) || ' months')::interval)
  AND NOT pass
