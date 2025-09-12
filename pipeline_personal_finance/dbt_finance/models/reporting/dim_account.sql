with subquery as (
    select distinct
        account_foreign_key as origin_key,
        trim(
            case
                when account_foreign_key like '%_Homeloan%' then split_part(account_foreign_key, '_Homeloan', 1)
                when account_foreign_key like '%_Offset%' then split_part(account_foreign_key, '_Offset', 1)
                else split_part(account_foreign_key, '_', 1)
            end
        ) as bank_name,
        trim(
            case
                when account_foreign_key like '%_Homeloan%' then 'Homeloan'
                when account_foreign_key like '%_Offset%' then 'Offset'
                else split_part(split_part(account_foreign_key, '_', 2), '_Transactions.qif', 1)
            end
        ) as account_name,
        cast(date as date) as date
from {{ ref('fct_transactions_enhanced') }}
),

final as (
    select
        row_number() over () as surrogate_key,
        origin_key,
        bank_name,
        account_name,
        min(date) as start_date,
        max(date) as end_date
    from
        subquery
    group by
        origin_key,
        bank_name,
        account_name
)


select * from final
