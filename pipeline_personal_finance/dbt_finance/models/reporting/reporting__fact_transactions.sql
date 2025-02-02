select
    row_number() over () as surrogate_key,
    trans.date,
    trans.amount,
    trans.adjusted_balance as balance,
    trans.memo,
    trans.transaction_type,
    trans.account_name as account_foreign_key,
    trans.category_foreign_key,
    case
        when trans.amount > 0 then 'DEBIT'
        when trans.amount < 0 then 'CREDIT'
        else 'NEURAL'
    end as amount_type,
    coalesce(cat.internal_indicator, 'UNCATEGORISED') as internal_indicator
from {{ ref('trans_categories') }} as trans
left join {{ ref('dim_category') }} as cat
    on trans.category_foreign_key = cat.origin_key
