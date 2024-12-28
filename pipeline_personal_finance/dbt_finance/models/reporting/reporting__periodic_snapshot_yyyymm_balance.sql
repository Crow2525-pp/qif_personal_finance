with Calendar as (
    select Date
    from {{ ref('date_calendar') }}
),

Accountbalances as (
    select
        Account_foreign_key,
        Date,
        Balance
    from
        {{ ref("reporting__fact_transactions") }}
    where
        upper(Internal_indicator) != 'INTERNAL'
),

Balances_with_dates as (
    select
        to_char(C.Date, 'YYYY-MM') as Year_month,
        Ab.Account_foreign_key,
        Ab.Balance
    from
        Calendar C
    left join Accountbalances Ab on C.Date = Ab.Date
),

-- gets the last non-null array: https://stackoverflow.com/questions/56728095/postgresql-last-value-ignore-nulls
Latest_balances as (
    select
        Year_month,
        Account_foreign_key,
        -- Using ARRAY_REMOVE to discard nulls and then selecting the last non-null balance using array indexing
        (array_remove(
            array_agg(Balance) over (
                partition by
                    Account_foreign_key
                order by
                    Year_month
            ),
            NULL))[count(Balance) over (
            partition by
                Account_foreign_key
            order by Year_month
        )] as Latest_balance
    from Balances_with_dates
),

Final as (
    select
        Year_month,
        Account_foreign_key,
        Latest_balance
    from
        Latest_balances
    order by
        Year_month, Account_foreign_key
)

select * from Final