{# Define your variables - these are the words/phrases you want to separate into a transaction type #}
{% set transaction_types = ['ANYPAY', 'BPAY', 'DIRECT CREDIT', 'RETAIL PURCHASE', 
'STANDING ORDER AUTOPAY', 'RETAIL PURCHASE', 'EFTPOS WITHDRAWAL', 
'DIRECT DEBIT', 'DIRECT CREDIT', 'BANK@POST PAYMEN', 'MONTHLY SERVICE FEE', 'INTEREST', 
'INTERNET TRANSFER CREDIT', 'DRAW DOWN NETT ADVANCE', 'ESTABLISHMENT FEE', 'DRAW DOWN DISBURSEMENTS',
'DRAW DOWN REGISTRATION FEE', 'TRANSFER'] %}

with cleaned_memo_data as (
    SELECT
        primary_key,
        -- Normalize the delimiters and split the memo field into an array
        regexp_split_to_array(regexp_replace(memo, '{{ transaction_types | join('|') }}', ''), ' - ') AS Split_Memo,
        -- Replace the transaction_types with an empty string
        regexp_replace(memo, '{{ transaction_types | join('|') }}', '') AS Transaction_Description,
        -- Extract the first occurrence of any transaction type using regex
        (regexp_matches(memo, '{{ transaction_types | join('|') }}'))[1] AS Transaction_Type
    FROM
        {{ source('personalfinance_dagster', 'Bendigo_Bank_Homeloan_Transactions') }}
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
    '' as sender,
    '' as recepient,
    trim(c.Transaction_Description) as Transaction_Description,
    trim(c.Transaction_Type) as Transaction_Type,
    cast(a.amount as float) as amount,
    a.line_number,    
    c.primary_key,
    current_date,
    current_time,
    'adelaide_homeloan' as account_name

FROM {{ source('personalfinance_dagster', 'Bendigo_Bank_Homeloan_Transactions') }} as a
left join cleaned_memo_data as c
on a.primary_key = c.primary_key
