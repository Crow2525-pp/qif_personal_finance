{% macro calculate_adjusted_balance(table_name) %}
{% set account_name = table_name | replace('staging__', '') %}

WITH transactions_with_balance AS (
    SELECT *,
           CAST(SUM(amount) OVER (
               ORDER BY line_number DESC 
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS decimal(14,2)) AS balance
    FROM {{ ref(table_name) }}
),
balance_adjustment AS (
    SELECT balance - CAST((SELECT known_balance FROM {{ ref('known_values') }} WHERE account_name = '{{ account_name }}') AS decimal(14,2)) AS adjustment
    FROM transactions_with_balance
    WHERE date = (SELECT specific_date FROM {{ ref('known_values') }} WHERE account_name = '{{ account_name }}')
    LIMIT 1
),
adjusted_transactions AS (
    SELECT t.*,
           t.balance - b.adjustment AS adjusted_balance
    FROM transactions_with_balance t
    JOIN balance_adjustment b ON t.line_number = b.line_number
)
SELECT * FROM adjusted_transactions
{% endmacro %}
