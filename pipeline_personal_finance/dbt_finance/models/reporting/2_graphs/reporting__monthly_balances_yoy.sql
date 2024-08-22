with final as (
SELECT 
    TO_CHAR(date, 'YYYY-MM') AS year_month, 
    latest_balance,
    row_number() Over(
        partition by 
            account_name,
            TO_CHAR(date, 'YYYY-MM')
        order by
            date desc
    ) as last_rn
FROM 
    {{ ref("reporting__last_balance") }}
)

select 
    year_month,
    sum(latest_balance) as net_position
from final
where last_rn = 1
and latest_balance is not null
group by year_month