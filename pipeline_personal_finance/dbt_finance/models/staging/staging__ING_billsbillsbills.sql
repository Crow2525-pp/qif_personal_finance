WITH cleaned_memo_data AS (
    SELECT
        a.primary_key,
        a.payee as memo,
        regexp_split_to_array(a.payee, ' - ') AS Split_Memo,
        r.Receipt,
        l.Location,
        d.Description_Date,
        cn.Card_No,
        f.sender,
        t.recepient
    FROM 
        {{ source('personalfinance_dagster', 'ING_BillsBillsBills_Transactions') }} a
    LEFT JOIN LATERAL (SELECT (regexp_matches(a.payee, 'Receipt (\d+)'))[1] AS Receipt) r ON a.payee ~ 'Receipt (\d+)' 
    LEFT JOIN LATERAL (SELECT (regexp_matches(a.payee, 'In ([A-Za-z\s]+) Date'))[1] AS Location) l ON a.payee ~ 'In ([A-Za-z\s]+) Date'
    LEFT JOIN LATERAL (SELECT (regexp_matches(a.payee, 'Date (\d{2} [A-Za-z]{3} \d{4})'))[1] AS Description_Date) d ON a.payee ~ 'Date (\d{2} [A-Za-z]{3} \d{4})'
    LEFT JOIN LATERAL (SELECT (regexp_matches(a.payee, 'Card ([\dx]+)$'))[1] AS Card_No) cn ON a.payee ~ 'Card ([\dx]+)$'
    LEFT JOIN LATERAL (SELECT (regexp_matches(a.payee, 'From ([A-Za-z\s]+)$'))[1] AS sender) f ON a.payee ~ 'From ([A-Za-z\s]+)$'
    LEFT JOIN LATERAL (SELECT (regexp_matches(a.payee, 'To ([A-Za-z\s]+)$'))[1] AS recepient) t ON a.payee ~ 'To ([A-Za-z\s]+)$'
)


SELECT 
    cast(date_trunc('day', a.date) as date) as date,
    COALESCE(trim((c.Split_Memo)[1]), NULL) AS Transaction_Description, 
    COALESCE(trim((c.Split_Memo)[2]), NULL) AS Transaction_Type, 
    trim(c.memo) as memo,
    trim(c.Receipt) as Receipt,
    trim(c.Location) as Location,
    c.Description_Date,
    trim(c.Card_No) as Card_No,
    trim(c.sender) as sender,
    trim(c.recepient) as recepient,
    cast(a.amount as float) as amount,
    a.line_number,    
    a.primary_key,
    current_date,
    current_time,
    'ing_billsbillsbills' as account_name
FROM {{ source('personalfinance_dagster', 'ING_BillsBillsBills_Transactions') }} as a
left join cleaned_memo_data as c
on a.primary_key = c.primary_key
