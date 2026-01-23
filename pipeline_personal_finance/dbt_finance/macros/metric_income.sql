{% macro metric_income(table_alias='ft') %}
  CASE
    WHEN COALESCE({{ table_alias }}.is_internal_transfer, FALSE) THEN 0
    WHEN COALESCE({{ table_alias }}.is_income_transaction, FALSE) THEN ABS({{ table_alias }}.transaction_amount)
    WHEN {{ table_alias }}.transaction_amount > 0 THEN ABS({{ table_alias }}.transaction_amount)
    ELSE 0
  END
{% endmacro %}
