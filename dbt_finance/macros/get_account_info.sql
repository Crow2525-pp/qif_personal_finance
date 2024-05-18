{% macro get_account_info(account_name, info_key) %}
  {% set account_data = var('account_info')[account_name] %}
  
  {% do log("Debug: account_name is " ~ account_name, info=True) %}
  {% do log("Debug: info_key is " ~ info_key, info=True) %}
  {% do log("Debug: account_data is " ~ account_data, info=True) %}
  
  {{ account_data[info_key] if info_key in account_data else none }}
{% endmacro %}