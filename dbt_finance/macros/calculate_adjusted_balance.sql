{% macro calculate_adjusted_balance(table_name) %}
  {% set short_table_name = table_name.identifier %} -- Directly accessing the identifier
  
  {% set known_balance = get_account_info(short_table_name, 'known_balance') | trim %}
  {% set specific_date = get_account_info(short_table_name, 'specific_date') | trim %}

  {{ log("Debug: known_balance for " ~ table_name ~ " is " ~ known_balance | trim, info=True) }}
  {{ log("Debug: specific_date for " ~ table_name ~ " is " ~ specific_date| trim, info=True) }}

  WITH transactions_with_balance AS (
    SELECT *,
      CAST(SUM(amount) OVER (
        ORDER BY line_number DESC 
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS decimal(14,2)) AS balance
      FROM {{ table_name }}
  ),
  balance_adjustment AS (
      SELECT balance - {{ known_balance }} AS adjustment
      FROM transactions_with_balance
      WHERE date = '{{ specific_date }}'
      LIMIT 1
  ),
  adjusted_transactions AS (
      SELECT t.*,
             t.balance - b.adjustment AS adjusted_balance
      FROM transactions_with_balance t, balance_adjustment b
      order by line_number DESC
  )
  
  {{ log("Debug: SQL for transactions_with_balance: " ~ "  SELECT line_number, date, amount,
             SUM(amount) OVER (ORDER BY line_number DESC ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS running_total
      FROM " ~ table_name| trim, info=True) }}
  
  {{ log("Debug: SQL for balance_adjustment: " ~ "SELECT running_total - "~ known_balance ~
  "AS adjustment FROM transactions_with_balance WHERE date = '"~ specific_date ~"' LIMIT 1"| trim, info=True) }}
  
  SELECT * FROM adjusted_transactions
  ORDER BY line_number DESC

{% endmacro %}
