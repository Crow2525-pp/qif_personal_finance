{% set transaction_types = [
    'ANYPAY', 'BPAY', 'DIRECT CREDIT', 'RETAIL PURCHASE', 
    'STANDING ORDER AUTOPAY', 'EFTPOS WITHDRAWAL', 'DIRECT DEBIT', 
    'BANK@POST PAYMEN', 'MONTHLY ADMINISTRATION FEE', 'DEBIT INTEREST', 
    'INTERNET TRANSFER CREDIT', 'ADVANCE'
] %}

WITH parsed_memo_data AS (
    SELECT
        primary_key,
        -- Remove transaction types and normalize the memo field
        regexp_replace(memo, '{{ transaction_types | join('|') }}', '', 'g') AS transaction_description,
        
        -- Extract the first matching transaction type
        (regexp_matches(memo, '{{ transaction_types | join('|') }}'))[1] AS transaction_type,

        -- Split memo into an array using " - " as a delimiter
        regexp_split_to_array(regexp_replace(memo, '{{ transaction_types | join('|') }}', '', 'g'), ' - ') AS split_memo
    FROM {{ source('personalfinance_dagster', 'Bendigo_Offset_Transactions') }}
)

SELECT 
    -- Normalize the date column
    CAST(DATE_TRUNC('day', transactions.date) AS DATE) AS transaction_date,
    
    -- Cleaned memo field
    TRIM(transactions.memo) AS memo,
    
    -- Additional blank columns for future processing
    '' AS receipt,
    '' AS location,
    '' AS description_date,
    '' AS card_no,
    '' AS sender,
    '' AS recipient,
    
    -- Extracted and cleaned transaction description and type
    TRIM(COALESCE(parsed_memo.transaction_description, '')) AS transaction_description,
    TRIM(COALESCE(parsed_memo.transaction_type, '')) AS transaction_type,

    -- Ensure amount is cast properly
    COALESCE(CAST(transactions.amount AS FLOAT), 0) AS transaction_amount,
    
    -- Maintain primary keys for reference
    transactions.line_number,    
    transactions.primary_key,

    -- Add metadata columns
    CURRENT_DATE AS etl_date,
    CURRENT_TIME AS etl_time,
    'bendigo_offset' AS account_name

FROM {{ source('personalfinance_dagster', 'Bendigo_Offset_Transactions') }} AS transactions
LEFT JOIN parsed_memo_data AS parsed_memo
    ON transactions.primary_key = parsed_memo.primary_key
