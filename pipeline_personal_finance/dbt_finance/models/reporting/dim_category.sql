select 
  origin_key,
  transaction_description,
  transaction_type,
  sender,
  recipient,
  account_name,
  category,
  subcategory,
  store,
  internal_indicator
from {{ ref('banking_categories') }}

-- TODO: replace category with category_name.
