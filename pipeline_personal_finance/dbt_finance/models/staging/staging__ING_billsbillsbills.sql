with cleaned_memo_data as (
    select
        a.primary_key,
        a.payee as memo,
        regexp_split_to_array(a.payee, ' - ') as split_memo,
        r.receipt,
        l.location,
        d.description_date,
        cn.card_no,
        f.sender,
        t.recipient
    from
        {{ source('personalfinance_dagster', 'ING_BillsBillsBills_Transactions') }} a
    left join lateral (select (regexp_matches(a.payee, 'Receipt (\d+)'))[1] as receipt) r on a.payee ~ 'Receipt (\d+)'
    left join
        lateral (select (regexp_matches(a.payee, 'In ([A-Za-z\s]+) Date'))[1] as location) l
        on a.payee ~ 'In ([A-Za-z\s]+) Date'
    left join
        lateral (select (regexp_matches(a.payee, 'Date (\d{2} [A-Za-z]{3} \d{4})'))[1] as description_date) d
        on a.payee ~ 'Date (\d{2} [A-Za-z]{3} \d{4})'
    left join
        lateral (select (regexp_matches(a.payee, 'Card ([\dx]+)$'))[1] as card_no) cn
        on a.payee ~ 'Card ([\dx]+)$'
    left join
        lateral (select (regexp_matches(a.payee, 'From ([A-Za-z\s]+)$'))[1] as sender) f
        on a.payee ~ 'From ([A-Za-z\s]+)$'
    left join
        lateral (select (regexp_matches(a.payee, 'To ([A-Za-z\s]+)$'))[1] as recipient) t
        on a.payee ~ 'To ([A-Za-z\s]+)$'
)


select
    cast(date_trunc('day', a.date) as date) as date,
    coalesce(trim((c.split_memo)[1]), NULL) as transaction_description,
    coalesce(trim((c.split_memo)[2]), NULL) as transaction_type,
    trim(c.memo) as memo,
    trim(c.receipt) as receipt,
    trim(c.location) as location,
    c.description_date,
    trim(c.card_no) as card_no,
    trim(c.sender) as sender,
    trim(c.recipient) as recipient,
    cast(a.amount as float) as amount,
    a.line_number,
    a.primary_key,
    current_date,
    current_time,
    'ing_billsbillsbills' as account_name
from {{ source('personalfinance_dagster', 'ING_BillsBillsBills_Transactions') }} as a
left join cleaned_memo_data as c
    on a.primary_key = c.primary_key
