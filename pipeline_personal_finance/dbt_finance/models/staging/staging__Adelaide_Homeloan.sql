{% set transaction_types = [
    'ANYPAY', 'BPAY', 'DIRECT CREDIT', 'RETAIL PURCHASE', 
    'STANDING ORDER AUTOPAY', 'EFTPOS WITHDRAWAL', 'DIRECT DEBIT', 
    'BANK@POST PAYMEN', 'MONTHLY ADMINISTRATION FEE', 'DEBIT INTEREST', 
    'INTERNET TRANSFER CREDIT', 'ADVANCE'
] %}

/* TODO: Rename "current_date" / "current_time" to ETL timestamp */
WITH parsed_memo_data AS (
    SELECT
        primary_key,
        -- Remove transaction types and normalize the memo field
        regexp_replace(memo, '{{ transaction_types | join('|') }}', '', 'g') AS transaction_description,
        
        -- Extract the first matching transaction type
        (regexp_matches(memo, '{{ transaction_types | join('|') }}'))[1] AS transaction_type,

        -- Split memo into an array using " - " as a delimiter
        regexp_split_to_array(regexp_replace(memo, '{{ transaction_types | join('|') }}', '', 'g'), ' - ') AS split_memo
    FROM {{ source('personalfinance_dagster', 'Adelaide_Homeloan_Transactions') }}
)

SELECT
    -- Additional blank fields for potential future use
    '' AS receipt,
    '' AS location,
    '' AS description_date,
    '' AS card_no,
    '' AS sender,
    '' AS recipient,
    
    -- Transaction details
    CAST(transactions.amount AS FLOAT) AS transaction_amount,
    transactions.line_number,
    transactions.primary_key,
    
    -- Account and source information
    'adelaide_homeloan' AS account_name,
    
    -- Normalize the date column
    CAST(DATE_TRUNC('day', transactions.date) AS DATE) AS transaction_date,

    -- Memo and extracted details
    TRIM(transactions.memo) AS memo,
    TRIM(COALESCE(parsed_memo.transaction_description, '')) AS transaction_description,
    TRIM(COALESCE(parsed_memo.transaction_type, '')) AS transaction_type,

    -- ETL metadata columns
    CURRENT_DATE AS etl_date,
    CURRENT_TIME AS etl_time

FROM {{ source('personalfinance_dagster', 'Adelaide_Homeloan_Transactions') }} AS transactions
LEFT JOIN parsed_memo_data AS parsed_memo
    ON transactions.primary_key = parsed_memo.primary_key
