WITH cleaned_memo_data AS (
    SELECT
        a.primary_key,
        a.payee as memo,
        regexp_split_to_array(a.payee, ' - ') AS Split_Memo,
        r.Receipt,
        l.Location,
        d.Description_Date,
        cn.Card_No,
        f."From",
        t."To"
    FROM {{ source('personalfinance_dagster', 'ING_Countdown_Transactions') }} a
    LEFT JOIN LATERAL (SELECT (regexp_matches(a.payee, 'Receipt (\d+)'))[1] AS Receipt) r ON true
    LEFT JOIN LATERAL (SELECT (regexp_matches(a.payee, 'In ([A-Za-z\s]+) Date'))[1] AS Location) l ON true
    LEFT JOIN LATERAL (SELECT (regexp_matches(a.payee, 'Date (\d{2} [A-Za-z]{3} \d{4})'))[1] AS Description_Date) d ON true
    LEFT JOIN LATERAL (SELECT (regexp_matches(a.payee, 'Card ([\dx]+)$'))[1] AS Card_No) cn ON true
    LEFT JOIN LATERAL (SELECT (regexp_matches(a.payee, 'From ([A-Za-z\s]+)$'))[1] AS "From") f ON true
    LEFT JOIN LATERAL (SELECT (regexp_matches(a.payee, 'To ([A-Za-z\s]+)$'))[1] AS "To") t ON true
)

SELECT 
    date_trunc('day', a.date) as date,
    COALESCE(trim((c.Split_Memo)[1]), NULL) AS Transaction_Description, 
    COALESCE(trim((c.Split_Memo)[2]), NULL) AS Transaction_Type, 
    trim(c.memo) as memo,
    c.Receipt,
    trim(c.Location) as Location,
    c.Description_Date,
    trim(c.Card_No) as Card_No,
    trim(c."From") as "From",
    trim(c."To") as "To",
    cast(a.amount as float) as amount,
    a.line_number,    
    a.primary_key,
    current_date,
    current_time,
    'ING_countdown' as Account
FROM {{ source('personalfinance_dagster', 'ING_Countdown_Transactions') }} as a
LEFT JOIN cleaned_memo_data as c
ON a.primary_key = c.primary_key
