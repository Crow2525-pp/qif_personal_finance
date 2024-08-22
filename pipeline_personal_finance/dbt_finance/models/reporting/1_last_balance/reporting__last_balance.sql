WITH Calendar AS (
    SELECT DATE
    FROM {{ ref('date_calendar') }}  -- This references the date_calendar model you've created
),
AccountBalances AS (
    SELECT
        account_name,
        DATE,
        balance
    FROM
        {{ ref("reporting__fresh_table") }}  -- Reference to another table/model in your dbt project
),
balances_with_dates AS (
    SELECT
        c.DATE,
        ab.account_name,
        ab.balance
    FROM
        Calendar c
        LEFT JOIN AccountBalances ab ON c.DATE = ab.DATE
),
--gets the last non-null array: https://stackoverflow.com/questions/56728095/postgresql-last-value-ignore-nulls
latest_balances AS (
    SELECT
        DATE,
        account_name,
 		(ARRAY_REMOVE(ARRAY_AGG(balance) OVER (PARTITION BY account_name ORDER BY date), NULL))[COUNT(balance) OVER (PARTITION BY account_name ORDER BY date)] AS latest_balance
        FROM balances_with_dates
)
SELECT 
    DATE,
    account_name,
    latest_balance
FROM 
    latest_balances
ORDER BY 
    account_name, DATE
