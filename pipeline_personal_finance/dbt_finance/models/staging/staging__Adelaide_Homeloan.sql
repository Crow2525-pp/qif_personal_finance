{# These are the words/phrases you want to remove #}
{% set transaction_types = ['ANYPAY', 'BPAY', 'DIRECT CREDIT', 'RETAIL PURCHASE', 
'STANDING ORDER AUTOPAY', 'RETAIL PURCHASE', 'EFTPOS WITHDRAWAL', 
'DIRECT DEBIT', 'DIRECT CREDIT', 'BANK@POST PAYMEN', 'MONTHLY ADMINISTRATION FEE', 'DEBIT INTEREST', 
'INTERNET TRANSFER CREDIT', 'ADVANCE'] %}

/* TODO: Rename all cols - Current Date / Current Time to ETL DATETIME stamp
*/

with cleaned_memo_data as (
    select
        primary_key,
        -- Normalize the delimiters and split the memo field into an array
        regexp_split_to_array(
            regexp_replace(memo, '{{ transaction_types | join('|') }}', ''),
            ' - '
        ) as split_memo,
        -- Replace the transaction_types with an empty string
        regexp_replace(
            memo, '{{ transaction_types | join('|') }}', ''
        ) as transaction_description,
        -- Extract the first occurrence of any transaction type using regex
        (
            regexp_matches(memo, '{{ transaction_types | join('|') }}')
        )[1] as transaction_type
    from
        {{ source('personalfinance_dagster', 'Adelaide_Homeloan_Transactions') }}
)

select
    '' as receipt,
    --COALESCE(ARRAY_EXTRACT(c.Split_Memo, 1), NULL) AS Memo_Part_1,
    --COALESCE(ARRAY_EXTRACT(c.Split_Memo, 2), NULL) AS Memo_Part_2,
    --COALESCE(ARRAY_EXTRACT(c.Split_Memo, 3), NULL) AS Memo_Part_3, 
    --COALESCE(ARRAY_EXTRACT(c.Split_Memo, 4), NULL) AS Memo_Part_4,
    '' as location,
    '' as description_date,
    '' as card_no,
    '' as sender,
    '' as recepient,
    cast(a.amount as float) as amount,
    a.line_number,
    c.primary_key,
    'adelaide_homeloan' as account_name,
    date_trunc('day', a.date) as date,
    trim(a.memo) as memo,
    trim(c.transaction_description) as transaction_description,
    trim(c.transaction_type) as transaction_type,
    current_date,
    current_time

from
    {{ source('personalfinance_dagster', 'Adelaide_Homeloan_Transactions') }} as a
left join cleaned_memo_data as c
    on a.primary_key = c.primary_key
