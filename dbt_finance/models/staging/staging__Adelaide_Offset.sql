{# Define your variables - these are the words/phrases you want to remove #}
{% set transaction_types = ['ANYPAY', 'BPAY', 'DIRECT CREDIT', 'RETAIL PURCHASE', 
'STANDING ORDER AUTOPAY', 'RETAIL PURCHASE', 'EFTPOS WITHDRAWAL', 
'DIRECT DEBIT', 'DIRECT CREDIT', 'BANK@POST PAYMEN', 'MONTHLY ADMINISTRATION FEE', 'DEBIT INTEREST', 
'INTERNET TRANSFER CREDIT', 'ADVANCE'] %}

WITH cleaned_memo_data AS (
    SELECT
        primary_key,
        -- Normalize the delimiters and split the memo field
        string_split_regex(REGEXP_REPLACE(memo, '{{ transaction_types | join('|') }}', ''), ' - ') AS Split_Memo,
        -- Replace the transaction_types with an empty string
        trim(REGEXP_REPLACE(memo, '{{ transaction_types | join('|') }}', '')) AS Transaction_Description,
        -- Extract the transaction type using the transaction_types list
        regexp_extract(memo, '{{ transaction_types | join('|') }}') AS Transaction_Type
    FROM
        {{ source('personalfinance_dagster', 'Adelaide_Offset_Transactions') }}
)

SELECT 
    -- Extract date component and other parts from the original 'date' field
    date_trunc('day', a.date) as date,
    --COALESCE(ARRAY_EXTRACT(c.Split_Memo, 1), NULL) AS Memo_Part_1,
    --COALESCE(ARRAY_EXTRACT(c.Split_Memo, 2), NULL) AS Memo_Part_2,
    --COALESCE(ARRAY_EXTRACT(c.Split_Memo, 3), NULL) AS Memo_Part_3, 
    --COALESCE(ARRAY_EXTRACT(c.Split_Memo, 4), NULL) AS Memo_Part_4,
    trim(a.memo) as memo,
    '' as Receipt,
    '' as Location,
    '' as Description_Date,
    '' as Card_No,
    '' as "From",
    '' as To,
    -- Cleaned memo and extracted transaction type
    trim(c.Transaction_Description) as Transaction_Description,
    trim(c.Transaction_Type) as Transaction_Type,
    -- Other fields from the original table
    a.amount,
    a.line_number,    
    a.primary_key,
    -- Additional fields like current date and time
    current_date,
    current_time,
    'adelaide_offset' as Account
FROM {{ source('personalfinance_dagster', 'Adelaide_Offset_Transactions') }} as a
LEFT JOIN cleaned_memo_data as c
ON a.primary_key = c.primary_key

