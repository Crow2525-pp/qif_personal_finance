
WITH Calendar AS (
    -- Reference the calendar table correctly
    SELECT DATE
    FROM {{ ref('date_calendar') }}  -- This references the date_calendar model you've created
),
AccountBalances AS (
    SELECT
        account_name,
        DATE,
        ADJUSTED_BALANCE
    FROM
        {{ ref("trans_no_int_transfers") }}  -- Reference to another table/model in your dbt project
),
RankedBalances AS (
    SELECT
        c.DATE,
        ab.account_name,
        ab.ADJUSTED_BALANCE,
        COALESCE(
            LAG(ab.ADJUSTED_BALANCE) OVER (PARTITION BY ab.account_name ORDER BY c.DATE),
            ab.ADJUSTED_BALANCE
        ) AS LAST_KNOWN_BALANCE
    FROM
        Calendar c
        LEFT JOIN AccountBalances ab ON c.DATE = ab.DATE
    WHERE
        c.DATE >= (SELECT MIN(DATE) FROM AccountBalances) AND
        c.DATE <= (SELECT MAX(DATE) FROM AccountBalances)
)

SELECT
    DATE,
    account_name,
    LAST_KNOWN_BALANCE
FROM
    RankedBalances
ORDER BY
    account_name, DATE;
