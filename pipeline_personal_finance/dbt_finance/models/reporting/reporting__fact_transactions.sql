SELECT
    ROW_NUMBER() OVER () AS surrogate_key,
    trans.primary_key,
    
    -- Mapping transaction_date → date
    trans.transaction_date AS date,

    -- Mapping transaction_amount → amount
    trans.transaction_amount AS amount,

    -- Mapping adjusted_transaction_balance → balance
    trans.adjusted_transaction_balance AS balance,

    -- Mapping memo → memo
    trans.memo AS memo,

    -- Mapping transaction_type → transaction_type
    trans.transaction_type AS transaction_type,

    -- Mapping account_name → account_foreign_key
    trans.account_name AS account_foreign_key,

    -- Mapping category_foreign_key → category_foreign_key
    trans.category_foreign_key AS category_foreign_key,

    -- Retaining amount type logic
    CASE
        WHEN trans.transaction_amount > 0 THEN 'DEBIT'
        WHEN trans.transaction_amount < 0 THEN 'CREDIT'
        ELSE 'NEURAL'
    END AS amount_type,

    -- Mapping internal_indicator
    COALESCE(cat.internal_indicator, 'UNCATEGORISED') AS internal_indicator

FROM {{ ref('trans_categories') }} AS trans
LEFT JOIN {{ ref('dim_category') }} AS cat
    ON trans.category_foreign_key = cat.origin_key
