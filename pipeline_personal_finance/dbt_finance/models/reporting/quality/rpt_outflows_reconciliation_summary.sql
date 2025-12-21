{{
    config(
        materialized='table',
        indexes=[
            {'columns': ['period_date'], 'unique': false},
            {'columns': ['status'], 'unique': false}
        ]
    )
}}

WITH latest AS (
    SELECT MAX(period_date) AS latest_period FROM {{ ref('rpt_outflows_reconciliation_tests') }}
),

per_period AS (
    SELECT 
        period_date,
        COUNT(*) FILTER (WHERE pass)     AS passed,
        COUNT(*) FILTER (WHERE NOT pass) AS failed,
        COUNT(*)                         AS total,
        CASE WHEN COUNT(*) FILTER (WHERE NOT pass) = 0 THEN 'PASS' ELSE 'FAIL' END AS status
    FROM {{ ref('rpt_outflows_reconciliation_tests') }}
    GROUP BY 1
),

annotated AS (
    SELECT 
        p.*,
        (p.period_date = l.latest_period) AS is_latest
    FROM per_period p
    CROSS JOIN latest l
)

SELECT 
    period_date,
    passed,
    failed,
    total,
    status,
    is_latest,
    CURRENT_TIMESTAMP AS summarized_at
FROM annotated
ORDER BY period_date DESC

