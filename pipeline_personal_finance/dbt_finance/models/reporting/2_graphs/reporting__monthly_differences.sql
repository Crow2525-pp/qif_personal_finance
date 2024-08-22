with monthly_differences AS (
    SELECT 
        a.year_month,
        a.net_position - COALESCE(b.net_position, 0) AS MoM_difference
    FROM 
        {{ ref("reporting__monthly_balances_yoy") }} a
    LEFT JOIN 
        {{ ref("reporting__monthly_balances_yoy") }} b ON a.year_month = TO_CHAR(TO_DATE(b.year_month, 'YYYY-MM') + INTERVAL '1 month', 'YYYY-MM')
)
SELECT 
    *
FROM 
    monthly_differences
ORDER BY 
    year_month asc