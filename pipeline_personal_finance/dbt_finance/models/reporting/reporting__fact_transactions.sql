select
    date,
    amount,
    adjusted_balance as balance,
    memo,
    transaction_type,
    account_name as account_foreign_key,
    category_foreign_key,
    case
        when amount > 0 then 'DEBIT'
        when amount < 0 then 'CREDIT'
        else 'NEURAL'
    end as amount_type,
    COALESCE(internal_indicator, 'UNCATEGORISED') as internal_indicator
from {{ ref('trans_no_int_transfers') }}
