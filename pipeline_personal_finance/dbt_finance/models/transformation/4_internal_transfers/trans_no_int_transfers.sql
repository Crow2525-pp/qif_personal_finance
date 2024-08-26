{% set internal_transaction_types = ['Internal Transfer', 'STANDING ORDER AUTOPAY'] %}

select trans.*, cat.internal_indicator
from {{ ref('trans_categories') }} as trans
left join {{ ref ('dim_category')}} as cat
on trans.category_foreign_key= cat.origin_key
