with ranked_balances as (
Select 
    TO_CHAR(date, 'YYYY-MM') as year_month,
    extract(year from date) as year,
    extract(month from date) as month,
    account_name,
    latest_balance,
    row_number() over(
        partition by 
            TO_CHAR(date, 'YYYY-MM'), 
            account_name
        order by
            date desc
    ) as rn_last
from {{ ref("reporting__last_balance") }}

),

final as (
select 
    year_month,
    account_name,
    latest_balance

from ranked_balances
where rn_last = 1)

select * from final