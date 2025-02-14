WITH transaction_data AS (
    SELECT {{ dbt_utils.star(from=ref('transformation__append_accounts')) }}
    FROM {{ ref('transformation__append_accounts') }}
),

category_mappings AS (
    SELECT {{ dbt_utils.star(from=ref('dim_category')) }}
    FROM {{ ref('dim_category') }}
),

-- Join transactions with category mappings
categorised_transactions AS (
    SELECT
        {{ dbt_utils.star(from="transaction_data") }},
        -- Assign category key (NULL means uncategorized)
        category.origin_key AS category_foreign_key
    FROM transaction_data AS transactions
    LEFT JOIN category_mappings AS category
        ON
            UPPER(transactions.account_name) = UPPER(category.account_name)
            AND (
                -- Priority 1: Match on sender & recipient
                (
                    transactions.sender IS NOT NULL
                    AND transactions.recipient IS NOT NULL
                    AND category.sender IS NOT NULL
                    AND category.recipient IS NOT NULL
                    AND UPPER(transactions.sender) = UPPER(category.sender)
                    AND UPPER(transactions.recipient) = UPPER(category.recipient)
                )
                OR
                -- Priority 2: Match on transaction type
                (
                    transactions.transaction_type IS NOT NULL
                    AND category.transaction_type IS NOT NULL
                    AND UPPER(transactions.transaction_type) = UPPER(category.transaction_type)
                )
                OR
                -- Priority 3: Match on transaction description (memo)
                (
                    transactions.memo IS NOT NULL
                    AND category.transaction_description IS NOT NULL
                    AND transactions.memo ILIKE CONCAT('%', category.transaction_description, '%')
                )
            )
)

SELECT {{ dbt_utils.star(from="categorised_transactions") }}
FROM categorised_transactions
