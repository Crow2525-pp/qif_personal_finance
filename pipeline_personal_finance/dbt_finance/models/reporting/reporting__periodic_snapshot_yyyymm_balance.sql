WITH Calendar AS (
    SELECT DATE
    FROM {{ ref('date_calendar') }}
),
AccountBalances AS (
    SELECT
        account_foreign_key,
        category_foreign_key,
        DATE,
        balance
    FROM
        {{ ref("reporting__fact_transactions") }}
    WHERE
      upper(internal_indicator) = 'EXTERNAL'
),
balances_with_dates AS (
    SELECT
        TO_CHAR(c.date, 'YYYY-MM') as year_month,
        ab.account_foreign_key,
        ab.category_foreign_key,
        ab.balance
    FROM
        Calendar c
        LEFT JOIN AccountBalances ab ON c.DATE = ab.DATE
),
-- gets the last non-null array: https://stackoverflow.com/questions/56728095/postgresql-last-value-ignore-nulls
latest_balances AS (
    SELECT
        year_month,
        account_foreign_key,
        category_foreign_key,
        -- Using ARRAY_REMOVE to discard nulls and then selecting the last non-null balance using array indexing
        (ARRAY_REMOVE(
                ARRAY_AGG(balance) OVER (
                    PARTITION BY 
                        account_foreign_key, 
                        category_foreign_key
                    ORDER BY 
                        year_month), 
                    NULL))
        [COUNT(balance) OVER (
            PARTITION BY
                account_foreign_key, 
                category_foreign_key
            ORDER BY year_month
        )] AS latest_balance
    FROM balances_with_dates
),

final as (
SELECT 
    year_month,
    account_foreign_key,
    category_foreign_key,
    latest_balance
FROM 
    latest_balances
ORDER BY 
    year_month, account_foreign_key, category_foreign_key
)

select * from final