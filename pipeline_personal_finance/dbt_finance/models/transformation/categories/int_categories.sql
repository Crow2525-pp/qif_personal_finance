WITH transaction_data AS (
    SELECT {{ dbt_utils.star(from=ref('int_append_accounts')) }}
    FROM {{ ref('int_append_accounts') }}
),

category_mappings AS (
    SELECT 
        cat_trans.transaction_description,
        cat_trans.transaction_type,
        cat_trans.sender,
        cat_trans.recipient,
        cat_trans.account_name,
        -- mapped natural category components
        cat_trans.category AS map_category,
        cat_trans.subcategory AS map_subcategory,
        cat_trans.store AS map_store,
        cat_trans.internal_indicator AS map_internal_indicator,
        -- link to dim_category (3-part key)
        cat.origin_key AS dim_category_key
    FROM {{ ref('dim_categorise_transaction') }} as cat_trans
    LEFT JOIN {{ ref('dim_category')}} as cat
        ON cat.origin_key = cat_trans.category_foreign_key
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
                transactions.memo IS NOT NULL
                AND category.transaction_description IS NOT NULL
                AND transactions.memo ILIKE CONCAT('%', category.transaction_description, '%')
            ) THEN 3
            ELSE 999
        END AS match_priority
    FROM transaction_data AS transactions
    LEFT JOIN category_mappings AS category
        ON
            UPPER(transactions.account_name) = UPPER(category.account_name)
            AND (
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
                    transactions.memo IS NOT NULL
                    AND category.transaction_description IS NOT NULL
                    AND transactions.memo ILIKE CONCAT('%', category.transaction_description, '%')
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
    -- Build foreign key to dim_categories_enhanced (matches its category_key)
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
