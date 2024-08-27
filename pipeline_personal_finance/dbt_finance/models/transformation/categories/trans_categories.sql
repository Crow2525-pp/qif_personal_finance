-- transformation/trans_categories.sql

WITH transaction_data AS (
    SELECT * FROM {{ ref('transformation__append_accounts') }}
),

category_mappings AS (
    SELECT * FROM {{ ref('banking_categories') }}
),

-- Join transactions with mappings and categorize them
categorised_transactions AS (
    SELECT
        t.*,
        -- Null Value means uncat
        cm.origin_key AS category_foreign_key
    FROM transaction_data AS t
    LEFT JOIN category_mappings AS cm 
    ON upper(t.account_name) = upper(cm.account_name)
        AND (
        -- First priority: from/to fields
            (
                t.sender IS NOT NULL
                AND t.recipient IS NOT NULL
                AND (cm.sender IS NOT NULL AND cm.recipient IS NOT NULL)
                AND upper(t.sender) = upper(cm.sender)
                AND upper(t.recipient) = upper(cm.recipient)
            )
            OR
            -- Second priority: transaction type
            (
                t.transaction_type IS NOT NULL
                AND cm.transaction_type IS NOT NULL
                AND upper(t.transaction_type) = upper(cm.transaction_type)
            )
            OR
            -- Third priority: transaction description
            (
                t.transaction_description IS NOT NULL
                AND cm.transaction_description IS NOT NULL
                AND t.transaction_description ILIKE CONCAT('%', cm.transaction_description, '%')
            )
        )
)

SELECT *
FROM categorised_transactions
