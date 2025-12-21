-- Fails when any reconciliation check fails within the configured window
WITH params AS (
  SELECT COALESCE({{ var('recon_months_back', 12) }}, 12)::int AS months_back
),
windowed AS (
  SELECT *
  FROM {{ ref('rpt_outflows_reconciliation_tests') }}
  WHERE period_date >= (DATE_TRUNC('month', CURRENT_DATE) - (
          (SELECT months_back FROM params) || ' months'
      )::interval)
)
SELECT *
FROM windowed
WHERE NOT pass
