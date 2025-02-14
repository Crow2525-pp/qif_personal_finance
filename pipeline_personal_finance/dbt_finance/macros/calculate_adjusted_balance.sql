{% macro calculate_adjusted_balance(table_name) %}
    {% set account_name = table_name | replace('staging__', '') %}

WITH transactions_with_balance AS (
    SELECT {{  dbt_utils.star(from=ref(table_name)) }},
           CAST(SUM(transaction_amount) OVER (
               PARTITION BY 
                    account_name
                ORDER BY 
                    transaction_date ASC, 
                    line_number ASC
               ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
           ) AS DECIMAL(14,2)) AS transaction_balance
    FROM {{ ref(table_name) }}
),

known_values AS (
    SELECT 
        CAST(account_balance AS DECIMAL(14,2)) AS specific_balance,
        specific_date AS transaction_date,
        account_name
    FROM {{ ref('known_values') }}
    WHERE LOWER(account_name) = LOWER('{{ account_name }}')
),

balance_adjustment AS (
    SELECT 
        transactions.line_number, 
        transactions.transaction_balance - known.specific_balance AS adjustment
    FROM transactions_with_balance transactions
    LEFT JOIN known_values known
        ON LOWER(transactions.account_name) = LOWER(known.account_name)
    WHERE 
        transactions.transaction_date = known.transaction_date
),

adjusted_transactions AS (
    SELECT transactions.*,
           transactions.transaction_balance - COALESCE(balance_adjustment.adjustment, 0) 
           AS adjusted_transaction_balance
    FROM transactions_with_balance transactions
    CROSS JOIN balance_adjustment
)
SELECT * FROM adjusted_transactions
{% endmacro %}
