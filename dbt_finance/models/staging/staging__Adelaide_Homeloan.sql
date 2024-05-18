{# Define your variables - these are the words/phrases you want to remove #}
{% set transaction_types = ['ANYPAY', 'BPAY', 'DIRECT CREDIT', 'RETAIL PURCHASE', 
'STANDING ORDER AUTOPAY', 'RETAIL PURCHASE', 'EFTPOS WITHDRAWAL', 
'DIRECT DEBIT', 'DIRECT CREDIT', 'BANK@POST PAYMEN', 'MONTHLY ADMINISTRATION FEE', 'DEBIT INTEREST', 
'INTERNET TRANSFER CREDIT', 'ADVANCE'] %}


with cleaned_memo_data as (
    SELECT
        composite_key,
        -- Normalize the delimiters and split the memo field
        string_split_regex(REGEXP_REPLACE(memo, '{{ transaction_types | join('|') }}', ''), ' - ') AS Split_Memo,
        -- Replace the transaction_types with an empty string
        REGEXP_REPLACE(memo, '{{ transaction_types | join('|') }}', '') AS Transaction_Description,
        -- Extract the transaction type using the transaction_types list
        regexp_extract(memo, '{{ transaction_types | join('|') }}') AS Transaction_Type
    FROM
        {{ source('personalfinance_dagster', 'Adelaide_Homeloan_Transactions') }}
)

SELECT 
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
    trim(c.Transaction_Description) as Transaction_Description,
    trim(c.Transaction_Type) as Transaction_Type,
    a.amount,
    a.line_number,    
    c.composite_key,
    current_date,
    current_time,
    'adelaide_homeloan' as Account

FROM {{ source('personalfinance_dagster', 'Adelaide_Homeloan_Transactions') }} as a
left join cleaned_memo_data as c
on a.composite_key = c.composite_key
