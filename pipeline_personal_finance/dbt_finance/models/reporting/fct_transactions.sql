SELECT
    ROW_NUMBER() OVER () AS surrogate_key,
    trans.primary_key,
    trans.transaction_date AS date,
    round(trans.transaction_amount::numeric, 2) AS amount,
    trans.adjusted_transaction_balance AS balance,
    trans.memo,
    trans.transaction_type,
    trans.account_name AS account_foreign_key,
    trans.category_foreign_key,

    CASE
        WHEN trans.transaction_amount > 0 THEN 'DEBIT'
        WHEN trans.transaction_amount < 0 THEN 'CREDIT'
        ELSE 'NEUTRAL'
    END AS amount_type,

    COALESCE(cat.internal_indicator, 'UNCATEGORISED') AS internal_indicator

FROM {{ ref('int_categories') }} AS trans
LEFT JOIN {{ ref('dim_category') }} AS cat
    ON trans.category_foreign_key = cat.origin_key
