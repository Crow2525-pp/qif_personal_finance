{% set internal_transaction_types = ['Internal Transfer', 'STANDING ORDER AUTOPAY'] %}

select *,
  case
    when
      trim(lower(transaction_type)) not in (
          {{ "'" + "', '".join(internal_transaction_types | map('lower')) + "'" }}
      )
      {# and
      sender = ''
      and
      recipient = '' #}
      and
      category <> 'Internal Transfer'
    then 'INTERNAL'
    else 'EXTERNAL'
  end as INTERNAL_INDICATOR
from {{ ref('trans_categories') }}
