select
    account,
    date,
    amount,
    adjusted_balance as balance,
    memo,
    transaction_type,
    final_category as category,
    final_subcategory as subcategory,
    case
        when amount > 0 then 'DEBIT'
        when amount < 0 then 'CREDIT'
        else 'NEURAL'
    end as amount_type
from {{ ref('trans_no_int_transfers') }}
