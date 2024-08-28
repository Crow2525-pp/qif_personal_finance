with final as (
SELECT 
    year_month, 
    account_foreign_key,
    latest_balance,
    row_number() Over(
        partition by 
            year_month,
            account_foreign_key
        order by
            year_month desc
    ) as last_rn
FROM 
    {{ ref("reporting__periodic_snapshot_yyyymm_balance") }}
)

select 
    year_month,
    account_foreign_key,
    sum(latest_balance) as net_position
from final
where last_rn = 1
and latest_balance is not null
group by 1,2