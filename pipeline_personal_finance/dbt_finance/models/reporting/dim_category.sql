select
  distinct
    {{ dbt_utils.generate_surrogate_key([
      'category',
      'subcategory',
      'store']) }} as origin_key,
    category,
    subcategory,
    store,
    internal_indicator

from {{ ref('banking_categories') }}

-- TODO: replace category with category_name.
-- TODO: origin_key should be the primary key/merged key, but it seems like foreign key might be the origin-key
