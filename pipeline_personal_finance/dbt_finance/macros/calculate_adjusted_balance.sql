{% macro calculate_adjusted_balance(table_name) %}
    {% set account_name = table_name | replace('staging__', '') %}

WITH transactions_with_balance AS (
    SELECT *,
           CAST(SUM(amount) OVER (
               PARTITION BY account_name ORDER BY date DESC, line_number DESC
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS decimal(14,2)) AS balance
    FROM {{ ref(table_name) }}
),

known_values AS (
    SELECT 
        CAST(account_balance AS decimal(14,2)) AS specific_balance,
        specific_date,
        account_name
    FROM {{ ref('known_values') }}
    WHERE account_name = '{{ account_name }}'
),

balance_adjustment AS (
    SELECT 
        trans.line_number, 
        trans.balance - known.specific_balance AS adjustment
    FROM transactions_with_balance trans
    LEFT JOIN known_values known
        ON lower(trans.account_name) = lower(known.account_name)
    WHERE 
        trans.date = known.specific_date
),

adjusted_transactions AS (
    SELECT t.*,
           t.balance - COALESCE(b.adjustment, 0) AS adjusted_balance
    FROM transactions_with_balance t
    LEFT JOIN balance_adjustment b 
        ON t.line_number = b.line_number
)
SELECT * FROM adjusted_transactions
{% endmacro %}
