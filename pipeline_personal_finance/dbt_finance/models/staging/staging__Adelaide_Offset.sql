{# Define your variables - these are the words/phrases you want to remove #}
{% set transaction_types = ['ANYPAY', 'BPAY', 'DIRECT CREDIT', 'RETAIL PURCHASE', 
'STANDING ORDER AUTOPAY', 'RETAIL PURCHASE', 'EFTPOS WITHDRAWAL', 
'DIRECT DEBIT', 'DIRECT CREDIT', 'BANK@POST PAYMEN', 'MONTHLY ADMINISTRATION FEE', 'DEBIT INTEREST', 
'INTERNET TRANSFER CREDIT', 'ADVANCE'] %}

with cleaned_memo_data as (
    select
        primary_key,
        -- Normalize the delimiters and split the memo field into an array
        regexp_split_to_array(regexp_replace(memo, '{{ transaction_types | join('|') }}', ''), ' - ') as split_memo,
        -- Replace the transaction_types with an empty string
        regexp_replace(memo, '{{ transaction_types | join('|') }}', '') as transaction_description,
        -- Extract the first occurrence of any transaction type using regex
        (regexp_matches(memo, '{{ transaction_types | join('|') }}'))[1] as transaction_type
    from
        {{ source('personalfinance_dagster', 'Adelaide_Offset_Transactions') }}
)

select
    -- Extract date component and other parts from the original 'date' field
    cast(date_trunc('day', a.date) as date) as date,
    --COALESCE(ARRAY_EXTRACT(c.Split_Memo, 1), NULL) AS Memo_Part_1,
    --COALESCE(ARRAY_EXTRACT(c.Split_Memo, 2), NULL) AS Memo_Part_2,
    --COALESCE(ARRAY_EXTRACT(c.Split_Memo, 3), NULL) AS Memo_Part_3, 
    --COALESCE(ARRAY_EXTRACT(c.Split_Memo, 4), NULL) AS Memo_Part_4,
    trim(a.memo) as memo,
    '' as receipt,
    '' as location,
    '' as description_date,
    '' as card_no,
    '' as sender,
    '' as recipient,
    -- Cleaned memo and extracted transaction type
    trim(c.transaction_description) as transaction_description,
    trim(c.transaction_type) as transaction_type,
    -- Other fields from the original table
    cast(a.amount as float) as amount,
    a.line_number,
    a.primary_key,
    -- Additional fields like current date and time
    current_date,
    current_time,
    'adelaide_offset' as account_name
from {{ source('personalfinance_dagster', 'Adelaide_Offset_Transactions') }} as a
left join cleaned_memo_data as c
    on a.primary_key = c.primary_key

