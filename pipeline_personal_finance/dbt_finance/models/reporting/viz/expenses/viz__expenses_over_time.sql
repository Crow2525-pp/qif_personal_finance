with grouped as (
    select
        to_char(date, 'YYYY-MM') as "year_month",
        amount_type,
        account_foreign_key,
        category_foreign_key,
        sum(amount) as amount
    from {{ ref('reporting__fact_transactions') }} group by 1, 2, 3, 4
),

two_years as (
    select
        trans.year_month as "Year Month",
        sum(trans2.amount) * -1 as "Month LY",
        sum(trans.amount) * -1 as "Month TY"
    from grouped as trans
    left join grouped as trans2
        on
            trans.year_month = to_char(to_date(trans2.year_month, 'YYYY-MM') + INTERVAL '1 year', 'YYYY-MM')
            and trans.account_foreign_key = trans2.account_foreign_key
            and trans.category_foreign_key = trans2.category_foreign_key
    left join reporting.dim_category as cat
        on trans.category_foreign_key = cat.origin_key
    left join reporting.dim_account as acc
        on trans.account_foreign_key = acc.origin_key
    where
        upper(trans.amount_type) = 'CREDIT'
        and upper(cat.internal_indicator) = 'EXTERNAL'
        and upper(cat.subcategory) != 'MORTGAGE'
    group by trans.year_month
),

rolling_totals as (
    select
        "Year Month",
        "Month LY",
        "Month TY",
        sum("Month TY") over (
            order by to_date("Year Month", 'YYYY-MM')
            rows between 11 preceding and current row
        ) as "R12M TY",
        sum("Month LY") over (
            order by to_date("Year Month", 'YYYY-MM')
            rows between 11 preceding and current row
        ) as "R12M LY"
    from two_years
)

select
    to_timestamp("Year Month" || '-01', 'YYYY-MM-DD') as date,
    "Month LY", "Month TY", "R12M TY", "R12M LY"
from rolling_totals
where "Month LY" is not null
order by date
