WITH RankedBalances AS (
    SELECT
        Account,
        Category,
        subcategory,
        Date,
        adjusted_balance,
        ROW_NUMBER() OVER(PARTITION BY Account ORDER BY Date DESC) as rn, -- Rank for the most recent transaction
        ROW_NUMBER() OVER(PARTITION BY Account, YEAR(Date) ORDER BY Date DESC) as rn_year,
        ROW_NUMBER() OVER(PARTITION BY Account, YEAR(Date), QUARTER(Date) ORDER BY Date DESC) as rn_quarter,
        ROW_NUMBER() OVER(PARTITION BY Account, YEAR(Date), MONTH(Date) ORDER BY Date DESC) as rn_month,
        ROW_NUMBER() OVER(PARTITION BY Account, YEAR(Date), WEEK(Date) ORDER BY Date DESC) as rn_week,
        ROW_NUMBER() OVER(PARTITION BY Account, YEAR(Date), MONTH(Date), DAY(Date) ORDER BY Date DESC) as rn_day
    FROM
        {{ ref("trans_no_int_transfers") }}
)
SELECT
    Account,
    Category,
    subcategory,
    Date AS PeriodStart,
    CASE 
        WHEN rn_day = 1 THEN 'Day'
        WHEN rn_week = 1 THEN 'Week'
        WHEN rn_month = 1 THEN 'Month'
        WHEN rn_quarter = 1 THEN 'Quarter'
        WHEN rn_year = 1 THEN 'Year'
        ELSE NULL -- For safety, though each row should fit one of the above categories
    END AS PeriodType,
    adjusted_balance AS LatestBalance
FROM 
    RankedBalances
WHERE 
    rn_day = 1 OR rn_week = 1 OR rn_month = 1 OR rn_quarter = 1 OR rn_year = 1 -- Ensuring it's the latest for any period
