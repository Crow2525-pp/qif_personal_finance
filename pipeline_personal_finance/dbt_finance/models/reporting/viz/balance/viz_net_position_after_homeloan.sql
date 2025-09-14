with monthly_end_dates as (
SELECT 
    DATE_TRUNC('month', period_date) + INTERVAL '1 month' - INTERVAL '1 day' as month_end_date,
    DATE_TRUNC('month', period_date) as year_month,
    account_foreign_key,
    end_of_day_balance as latest_balance,
    row_number() Over(
        partition by 
            DATE_TRUNC('month', period_date),
            account_foreign_key
        order by
            period_date desc
    ) as last_rn
FROM 
    {{ ref("rpt_periodic_snapshot_yyyymm_balance") }}
)

select 
    year_month,
    account_foreign_key,
    sum(latest_balance) as net_position
from monthly_end_dates
where last_rn = 1
and latest_balance is not null
group by 1,2