select
    account as account,
    date,
    amount,
    case
        when amount > 0 then 'DEBIT'
        when amount < 0 then 'CREDIT'
        else 'NEURAL'
    end as amount_type,
    adjusted_balance as balance,
    memo,
    transaction_type as transaction_type,    
    final_category as category,
    final_subcategory as subcategory
from {{ ref('trans_no_int_transfers') }}
