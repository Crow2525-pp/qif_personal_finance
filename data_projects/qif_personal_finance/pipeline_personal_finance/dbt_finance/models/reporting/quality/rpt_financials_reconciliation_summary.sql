{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['period_date'], 'unique': false}
    ]
  )
}}

WITH per_period AS (
  SELECT 
    period_date,
    domain,
    COUNT(*) FILTER (WHERE pass)     AS passed,
    COUNT(*) FILTER (WHERE NOT pass) AS failed,
    COUNT(*)                         AS total
  FROM {{ ref('rpt_financials_reconciliation_tests') }}
  GROUP BY 1,2
),

summary AS (
  SELECT 
    period_date,
    SUM(passed) AS passed,
    SUM(failed) AS failed,
    SUM(total)  AS total,
    CASE WHEN SUM(failed) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
  FROM per_period
  GROUP BY 1
)

SELECT * FROM summary
ORDER BY period_date DESC

