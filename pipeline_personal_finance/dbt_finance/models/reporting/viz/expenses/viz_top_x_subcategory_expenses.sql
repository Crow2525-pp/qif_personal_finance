with final as (
    select
        round(sum(trans.amount * -1)::numeric, 2) as amount,
        cat.subcategory
    from {{ ref('reporting__fact_transactions') }} as trans
    left join {{ ref('dim_category') }} as cat
        on trans.category_foreign_key = cat.origin_key
    left join {{ ref('dim_account') }} as acc
        on trans.account_foreign_key = acc.origin_key
    where
        upper(trans.amount_type) = 'CREDIT'
        and upper(cat.internal_indicator) = 'EXTERNAL'
        and upper(cat.subcategory) != 'MORTGAGE'
        and trans.date >= current_date - interval '12 month'
    group by
        cat.subcategory

)

select * from final
order by amount desc
