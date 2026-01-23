{% macro metric_expense(exclude_mortgage=false, table_alias='ft', category_alias='dc') %}
  CASE
    WHEN {{ table_alias }}.transaction_amount < 0
      AND NOT COALESCE({{ table_alias }}.is_internal_transfer, FALSE)
      AND NOT COALESCE({{ table_alias }}.is_income_transaction, FALSE)
      AND NOT COALESCE({{ table_alias }}.is_financial_service, FALSE)
      {% if exclude_mortgage %}
      AND COALESCE({{ category_alias }}.level_1_category, '') <> 'Mortgage'
      {% endif %}
    THEN ABS({{ table_alias }}.transaction_amount)
    ELSE 0
  END
{% endmacro %}
