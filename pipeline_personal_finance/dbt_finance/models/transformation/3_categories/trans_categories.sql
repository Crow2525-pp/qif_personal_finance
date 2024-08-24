-- transformation/trans_categories.sql

WITH transaction_data AS (
    SELECT * FROM {{ ref('transformation__append_accounts') }}
),

category_mappings AS (
    SELECT * FROM {{ ref('banking_categories') }}
),

-- Join transactions with mappings and categorize them
categorized_transactions AS (
    SELECT
        t.*,
        -- Use COALESCE to handle cases where there might not be a match and you want a default value
        COALESCE(cm.origin_key, 'Uncategorised') AS category_foreign_key,
    FROM transaction_data AS t
    LEFT JOIN category_mappings AS cm 
    ON t.account_name = cm.account_name
        AND (
        -- First priority: from/to fields
            (
                t.sender IS NOT NULL
                AND t.recipient IS NOT NULL
                AND (cm.sender IS NOT NULL AND cm.recipient IS NOT NULL)
                AND t.sender = cm.sender
                AND t.recipient = cm.recipient
            )
            OR
            -- Second priority: transaction type
            (
                t.transaction_type IS NOT NULL
                AND cm.transaction_type IS NOT NULL
                AND t.transaction_type = cm.transaction_type
            )
            OR
            -- Third priority: transaction description
            (
                t.transaction_description IS NOT NULL
                AND cm.transaction_description IS NOT NULL
                AND t.transaction_description ILIKE '%'
                || cm.transaction_description
                || '%'
            )
        )
)

SELECT *
FROM categorized_transactions
