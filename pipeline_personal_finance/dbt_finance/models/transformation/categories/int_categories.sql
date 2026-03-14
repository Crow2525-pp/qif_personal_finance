WITH transaction_data AS (
    SELECT
        {{ dbt_utils.star(from=ref('int_append_accounts')) }},
        LOWER(REGEXP_REPLACE(COALESCE(TRIM(account_name), ''), '^[^_]+_', '')) AS canonical_account_name,
        NULLIF(UPPER(TRIM(sender)), '') AS sender_normalized,
        NULLIF(UPPER(TRIM(recipient)), '') AS recipient_normalized,
        NULLIF(UPPER(TRIM(transaction_type)), '') AS transaction_type_normalized,
        COALESCE(
            NULLIF(TRIM(transaction_description), ''),
            NULLIF(TRIM(memo), '')
        ) AS match_text
    FROM {{ ref('int_append_accounts') }}
),

category_mappings AS (
    SELECT
        NULLIF(TRIM(bc.transaction_description), '') AS transaction_description_pattern,
        NULLIF(UPPER(TRIM(bc.transaction_type)), '') AS transaction_type,
        NULLIF(UPPER(TRIM(bc.sender)), '') AS sender,
        NULLIF(UPPER(TRIM(bc.recipient)), '') AS recipient,
        NULLIF(
            LOWER(REGEXP_REPLACE(COALESCE(TRIM(bc.account_name), ''), '^[^_]+_', '')),
            ''
        ) AS canonical_account_name,
        bc.category AS map_category,
        bc.subcategory AS map_subcategory,
        bc.store AS map_store,
        bc.internal_indicator AS map_internal_indicator
    FROM {{ ref('banking_categories') }} bc
),

categorised_transactions AS (
    SELECT
        {{ dbt_utils.star(from=ref('int_append_accounts'), relation_alias='transactions') }},
        category.map_category AS matched_category,
        category.map_subcategory AS matched_subcategory,
        category.map_store AS matched_store,
        category.map_internal_indicator AS matched_internal_indicator,
        (
            CASE WHEN category.canonical_account_name IS NULL THEN 0 ELSE 1 END +
            CASE WHEN category.sender IS NULL THEN 0 ELSE 1 END +
            CASE WHEN category.recipient IS NULL THEN 0 ELSE 1 END +
            CASE WHEN category.transaction_type IS NULL THEN 0 ELSE 1 END +
            CASE WHEN category.transaction_description_pattern IS NULL THEN 0 ELSE 1 END
        ) AS match_specificity,
        LENGTH(COALESCE(category.transaction_description_pattern, '')) AS match_pattern_length
    FROM transaction_data AS transactions
    LEFT JOIN category_mappings AS category
        ON (
            category.canonical_account_name IS NULL
            OR transactions.canonical_account_name = category.canonical_account_name
        )
        AND (category.sender IS NULL OR transactions.sender_normalized = category.sender)
        AND (category.recipient IS NULL OR transactions.recipient_normalized = category.recipient)
        AND (category.transaction_type IS NULL OR transactions.transaction_type_normalized = category.transaction_type)
        AND (
            category.transaction_description_pattern IS NULL OR (
                transactions.match_text IS NOT NULL
                AND transactions.match_text ILIKE CONCAT('%', category.transaction_description_pattern, '%')
            )
        )
),

ranked AS (
    SELECT
        *,
        ROW_NUMBER() OVER (
            PARTITION BY primary_key
            ORDER BY
                match_specificity DESC,
                match_pattern_length DESC,
                transaction_date DESC,
                account_name ASC
        ) AS rn
    FROM categorised_transactions
)

SELECT
    {{ dbt_utils.star(from=ref('int_append_accounts')) }},
    CASE
        WHEN matched_category IS NULL THEN NULL
        ELSE MD5(
            CAST(matched_category AS TEXT) || '-' ||
            CAST(COALESCE(matched_subcategory, '_dbt_utils_surrogate_key_null_') AS TEXT) || '-' ||
            CAST(COALESCE(matched_store, '_dbt_utils_surrogate_key_null_') AS TEXT) || '-' ||
            CAST(COALESCE(matched_internal_indicator, '_dbt_utils_surrogate_key_null_') AS TEXT)
        )
    END AS category_foreign_key
FROM ranked
WHERE rn = 1
