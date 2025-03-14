with final as (
    select
        top(20)
        as amount_type,
        category_foreign_key,
        amount
    from {{ ref('reporting__fact_transactions') }}
    order by amount desc
)

select * from final
