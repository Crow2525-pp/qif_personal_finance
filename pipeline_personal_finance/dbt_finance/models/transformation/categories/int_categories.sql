WITH transaction_data AS (
    SELECT {{ dbt_utils.star(from=ref('int_append_accounts')) }}
    FROM {{ ref('int_append_accounts') }}
),

-- Get category mappings from the banking_categories seed
category_mappings AS (
    SELECT
        bc.transaction_description,
        bc.transaction_type,
        bc.sender,
        bc.recipient,
        bc.account_name,
        -- mapped natural category components
        bc.category AS map_category,
        bc.subcategory AS map_subcategory,
        bc.store AS map_store,
        bc.internal_indicator AS map_internal_indicator
    FROM {{ ref('banking_categories') }} bc
),

-- Join transactions with category mappings
categorised_transactions AS (
    SELECT
        {{ dbt_utils.star(from=ref('int_append_accounts'), relation_alias="transactions") }},
        -- Bring through matched category components
        category.map_category AS matched_category,
        category.map_subcategory AS matched_subcategory,
        category.map_store AS matched_store,
        category.map_internal_indicator AS matched_internal_indicator,
        -- Determine match priority for the joined mapping row
        CASE
            WHEN (
                transactions.sender IS NOT NULL
                AND transactions.recipient IS NOT NULL
                AND category.sender IS NOT NULL
                AND category.recipient IS NOT NULL
                AND UPPER(transactions.sender) = UPPER(category.sender)
                AND UPPER(transactions.recipient) = UPPER(category.recipient)
            ) THEN 1
            WHEN (
                transactions.transaction_type IS NOT NULL
                AND category.transaction_type IS NOT NULL
                AND UPPER(transactions.transaction_type) = UPPER(category.transaction_type)
            ) THEN 2
            WHEN (
                COALESCE(transactions.transaction_description, transactions.memo) IS NOT NULL
                AND category.transaction_description IS NOT NULL
                AND COALESCE(transactions.transaction_description, transactions.memo) ILIKE CONCAT('%', category.transaction_description, '%')
            ) THEN 3
            ELSE 999
        END AS match_priority
    FROM transaction_data AS transactions
    LEFT JOIN category_mappings AS category
        ON (
                (
                    transactions.sender IS NOT NULL
                    AND transactions.recipient IS NOT NULL
                    AND category.sender IS NOT NULL
                    AND category.recipient IS NOT NULL
                    AND UPPER(transactions.sender) = UPPER(category.sender)
                    AND UPPER(transactions.recipient) = UPPER(category.recipient)
                )
                OR (
                    transactions.transaction_type IS NOT NULL
                    AND category.transaction_type IS NOT NULL
                    AND UPPER(transactions.transaction_type) = UPPER(category.transaction_type)
                )
                OR (
                    COALESCE(transactions.transaction_description, transactions.memo) IS NOT NULL
                    AND category.transaction_description IS NOT NULL
                    AND COALESCE(transactions.transaction_description, transactions.memo) ILIKE CONCAT('%', category.transaction_description, '%')
                )
            )
),

ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY primary_key
            ORDER BY match_priority ASC, transaction_date DESC, account_name ASC
        ) AS rn
    FROM categorised_transactions
)

SELECT
    {{ dbt_utils.star(from=ref('int_append_accounts')) }},
    -- Build foreign key to dim_categories (matches its category_key)
    COALESCE(
      md5(
        CAST(COALESCE(matched_category, '_dbt_utils_surrogate_key_null_') AS TEXT) || '-' ||
        CAST(COALESCE(matched_subcategory, '_dbt_utils_surrogate_key_null_') AS TEXT) || '-' ||
        CAST(COALESCE(matched_store, '_dbt_utils_surrogate_key_null_') AS TEXT) || '-' ||
        CAST(COALESCE(matched_internal_indicator, '_dbt_utils_surrogate_key_null_') AS TEXT)
      ),
      NULL
    ) AS category_foreign_key
FROM ranked
WHERE rn = 1
