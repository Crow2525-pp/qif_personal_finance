{% macro metric_interest_payment(table_alias='ft', category_alias='dc') %}
  CASE
    WHEN COALESCE({{ table_alias }}.is_internal_transfer, FALSE) THEN 0
    WHEN UPPER(COALESCE({{ table_alias }}.transaction_type, '')) IN ('DEBIT INTEREST', 'INTEREST')
      OR LOWER(COALESCE({{ table_alias }}.transaction_memo, '')) LIKE '%interest%'
      OR LOWER(COALESCE({{ table_alias }}.transaction_description, '')) LIKE '%interest%'
      OR LOWER(COALESCE({{ category_alias }}.level_2_subcategory, '')) LIKE '%interest%'
      OR LOWER(COALESCE({{ category_alias }}.level_3_store, '')) LIKE '%interest%'
    THEN ABS({{ table_alias }}.transaction_amount)
    ELSE 0
  END
{% endmacro %}
