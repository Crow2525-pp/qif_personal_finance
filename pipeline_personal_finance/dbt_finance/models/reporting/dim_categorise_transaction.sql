select
    transaction_description,
    transaction_type,
    sender,
    recipient,
    account_name,
    category,
    subcategory,
    store,
    internal_indicator,
    {{ dbt_utils.generate_surrogate_key([
      'category',
      'subcategory',
      'store']) }} as category_foreign_key,
    {{ dbt_utils.generate_surrogate_key(['transaction_description', 
      'transaction_type',
      'sender',
      'recipient',
      'account_name',
      'category',
      'subcategory',
      'store',
      'internal_indicator']) }} as origin_key
from {{ ref('banking_categories') }}

-- TODO: replace category with category_name.
