WITH base_data AS (
    SELECT
        trans.transaction_date,
        trans.primary_key,
        trans.transaction_amount,
        trans.adjusted_transaction_balance,
        trans.account_name AS account_foreign_key,
        trans.category_foreign_key,
        trans.memo,
        trans.transaction_type,
        CASE
            WHEN trans.transaction_amount > 0 THEN 'DEBIT'
            WHEN trans.transaction_amount < 0 THEN 'CREDIT'
            ELSE 'NEUTRAL'
        END AS amount_type,
        COALESCE(cat.internal_indicator, 'UNCATEGORISED') AS internal_indicator
    FROM {{ ref('int_categories') }} AS trans
    LEFT JOIN {{ ref('dim_categories') }} AS cat
        ON trans.category_foreign_key = cat.category_key
),
daily_aggregates AS (
    SELECT
        transaction_date,
        account_foreign_key,
        category_foreign_key,
        COUNT(*) AS transaction_count,
        SUM(transaction_amount) AS total_amount,
        AVG(transaction_amount) AS average_amount,
        MAX(adjusted_transaction_balance) AS end_of_day_balance,
        COUNT(CASE WHEN amount_type = 'DEBIT' THEN 1 END) AS debit_count,
        COUNT(CASE WHEN amount_type = 'CREDIT' THEN 1 END) AS credit_count,
        MAX(internal_indicator) AS internal_indicator
    FROM base_data
    GROUP BY transaction_date, account_foreign_key, category_foreign_key
)
SELECT
    ROW_NUMBER() OVER (ORDER BY dc.date, da.account_foreign_key, da.category_foreign_key) AS surrogate_key,
    dc.date AS period_date,
    da.account_foreign_key,
    da.category_foreign_key,
    COALESCE(da.transaction_count, 0) AS transaction_count,
    COALESCE(da.total_amount, 0) AS total_amount,
    COALESCE(da.average_amount, 0) AS average_amount,
    COALESCE(da.end_of_day_balance, 0) AS end_of_day_balance,
    COALESCE(da.debit_count, 0) AS debit_count,
    COALESCE(da.credit_count, 0) AS credit_count,
    da.internal_indicator
FROM {{ ref('dim_date_calendar') }} dc
LEFT JOIN daily_aggregates da
    ON dc.date = da.transaction_date
ORDER BY dc.date, da.account_foreign_key, da.category_foreign_key
