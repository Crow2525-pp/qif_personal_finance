select
    account_name,
    date,
    amount,
    adjusted_balance as balance,
    memo,
    transaction_type,
    category_foreign_key,
    case
        when amount > 0 then 'DEBIT'
        when amount < 0 then 'CREDIT'
        else 'NEURAL'
    end as amount_type,
    internal_indicator
from {{ ref('trans_no_int_transfers') }}
