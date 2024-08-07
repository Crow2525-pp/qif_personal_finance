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
        COALESCE(cm.category, 'Uncategorised') AS category,
        COALESCE(cm.subcategory, 'Uncategorised') AS subcategory
    FROM transaction_data AS t
    LEFT JOIN category_mappings AS cm 
    ON t.account = cm.account
        AND (
        -- First priority: from/to fields
            (
                t.sender IS NOT NULL
                AND t.recepient IS NOT NULL
                AND (cm.sender IS NOT NULL AND cm.recepient IS NOT NULL)
                AND t.sender = cm.sender
                AND t.recepient = cm.recepient
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

SELECT
    *,
    -- The final selection can also be a place to apply additional logic if needed
    CASE
        WHEN category IS NULL THEN 'Uncategorised'
        WHEN subcategory IS NULL THEN 'Uncategorised'
        ELSE category
    END AS final_category,
    COALESCE (subcategory, 'Uncategorised') AS final_subcategory
FROM categorized_transactions
