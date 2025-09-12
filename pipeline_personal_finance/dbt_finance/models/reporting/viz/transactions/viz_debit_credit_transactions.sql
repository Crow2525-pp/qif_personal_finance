select 
    TO_CHAR(trans.date, 'YYYY-MM') as year_month,
    trans.amount,
    trans.amount_type,
    acc.origin_key as account_foreign_key,
    acc.account_name,
    acc.bank_name,
    cat.category,
    cat.subcategory,
    cat.store,
    cat.internal_indicator
from {{ ref("reporting__fact_transactions") }} as trans
left join {{ ref("dim_category") }} as cat
    on trans.category_foreign_key = cat.origin_key
left join {{ ref("dim_account") }} as acc
    on trans.account_foreign_key = acc.origin_key
