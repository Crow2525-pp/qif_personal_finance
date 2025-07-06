WITH transaction_data AS (
    SELECT {{ dbt_utils.star(from=ref('transformation__append_accounts')) }}
    FROM {{ ref('transformation__append_accounts') }}
),

category_mappings AS (
    SELECT 
        {{ dbt_utils.star(from=ref('dim_categorise_transaction'), relation_alias='cat_trans', except=['origin_key']) }},
        {{ dbt_utils.star(from=ref('dim_category'), relation_alias='cat') }}
    FROM {{ ref('dim_categorise_transaction') }} as cat_trans
    left join {{ ref('dim_category')}} as cat
        ON cat.origin_key = cat_trans.category_foreign_key
),

-- Join transactions with category mappings
categorised_transactions AS (
    SELECT
        {{ dbt_utils.star(from=ref('transformation__append_accounts'), relation_alias="transactions") }},
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

SELECT * 
FROM categorised_transactions
