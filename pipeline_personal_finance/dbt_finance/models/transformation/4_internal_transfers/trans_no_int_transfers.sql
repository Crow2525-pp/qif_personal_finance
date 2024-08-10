{% set internal_transaction_types = ['Internal Transfer', 'STANDING ORDER AUTOPAY'] %}

select *
from {{ ref('trans_categories') }}
where
    trim(lower(transaction_type)) not in (
        {{ "'" + "', '".join(internal_transaction_types | map('lower')) + "'" }}
    )
    {# and
    sender = ''
    and
    recepient = '' #}
    and
    category <> 'Internal Transfer'
