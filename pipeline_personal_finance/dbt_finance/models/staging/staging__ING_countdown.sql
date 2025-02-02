with cleaned_memo_data as (
    select
        a.primary_key,
        a.payee as memo,
        r.receipt,
        l.location,
        d.description_date,
        cn.card_no,
        f.sender,
        t.recipient,
        regexp_split_to_array(a.payee, ' - ') as split_memo
    from
        {{ source('personalfinance_dagster', 'ING_Countdown_Transactions') }} as a
    left join
        lateral (
            select (regexp_matches(a.payee, 'Receipt (\d+)'))[1] as receipt
        ) as r
        on true
    left join
        lateral (
            select
                (regexp_matches(a.payee, 'In ([A-Za-z\s]+) Date'))[
                    1
                ] as location
        ) as l
        on true
    left join
        lateral (
            select
                (regexp_matches(a.payee, 'Date (\d{2} [A-Za-z]{3} \d{4})'))[
                    1
                ] as description_date
        ) as d
        on true
    left join
        lateral (
            select (regexp_matches(a.payee, 'Card ([\dx]+)$'))[1] as card_no
        ) as cn
        on true
    left join
        lateral (
            select (regexp_matches(a.payee, 'From ([A-Za-z\s]+)$'))[1] as sender
        ) as f
        on true
    left join
        lateral (
            select (regexp_matches(a.payee, 'To ([A-Za-z\s]+)$'))[1] as recipient
        ) as t
        on true
)

select
    c.receipt,
    c.description_date,
    cast(a.amount as float) as amount,
    a.line_number,
    a.primary_key,
    'ing_countdown' as account_name,
    cast(date_trunc('day', a.date) as date) as date,
    coalesce(trim((c.split_memo)[1]), null) as transaction_description,
    coalesce(trim((c.split_memo)[2]), null) as transaction_type,
    trim(c.memo) as memo,
    trim(c.location) as location,
    trim(c.card_no) as card_no,
    trim(c.sender) as sender,
    trim(c.recipient) as recipient,
    current_date,
    current_time
from {{ source('personalfinance_dagster', 'ING_Countdown_Transactions') }} as a
left join cleaned_memo_data as c
    on a.primary_key = c.primary_key
