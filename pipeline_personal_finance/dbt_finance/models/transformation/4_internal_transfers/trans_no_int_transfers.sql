{% set internal_transaction_types = ['Internal Transfer', 'STANDING ORDER AUTOPAY'] %}

select *
from {{ ref('trans_categories') }}
where 
    trim(lower(transaction_type)) NOT IN ({{ "'" + "', '".join(internal_transaction_types | map('lower')) + "'" }})
    AND
    "FROM" = ''
    AND
    "TO" = ''
    and 
    category <> 'Internal Transfer'