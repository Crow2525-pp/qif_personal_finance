WITH cleaned_memo_data AS (
    SELECT
        primary_key,
        payee as memo,
        -- Split the payee string into an array using a comma as the delimiter
        string_split_regex(payee, ' - ') AS Split_Memo,
        -- Extract Receipt Number (assuming it's always followed by a space or end of string)
        CASE 
            WHEN regexp_extract(payee, 'Receipt (\d+)') IS NOT NULL 
            THEN regexp_extract(payee, 'Receipt (\d+)', 1)
            ELSE NULL 
        END AS Receipt,
        -- Extract Location (if follows the pattern)
        CASE 
            WHEN regexp_extract(payee, 'In ([A-Za-z\s]+) Date') IS NOT NULL 
            THEN regexp_extract(payee, 'In ([A-Za-z\s]+) Date', 1) 
            ELSE NULL 
        END AS Location,
        -- Extract Date (if follows the pattern)
        CASE 
            WHEN regexp_extract(payee, 'Date (\d{2} [A-Za-z]{3} \d{4})') IS NOT NULL 
            THEN regexp_extract(payee, 'Date (\d{2} [A-Za-z]{3} \d{4})', 1) 
            ELSE NULL 
        END AS Description_Date,
        -- Extract Card Number (if follows the pattern)
        CASE 
            WHEN regexp_extract(payee, 'Card ([\dx]+)$') IS NOT NULL 
            THEN regexp_extract(payee, 'Card ([\dx]+)$', 1) 
            ELSE NULL 
        END AS Card_No,
        CASE 
            WHEN regexp_extract(payee, 'From ([A-Za-z\s]+)$') IS NOT NULL 
            THEN regexp_extract(payee, 'From ([A-Za-z\s]+)$', 1) 
            ELSE NULL 
        END AS "From",
        -- Extract To Account
        CASE 
            WHEN regexp_extract(payee, 'To ([A-Za-z\s]+)$') IS NOT NULL 
            THEN regexp_extract(payee, 'To ([A-Za-z\s]+)$', 1) 
            ELSE NULL 
        END AS "To"

    FROM
        {{ source('personalfinance_dagster', 'ING_BillsBillsBills_Transactions') }}
)


SELECT 
    date_trunc('day', a.date) as date,
    COALESCE(trim(ARRAY_EXTRACT(c.Split_Memo, 1)), NULL) AS Transaction_Description, 
    COALESCE(trim(ARRAY_EXTRACT(c.Split_Memo, 2)), NULL) AS Transaction_Type, 
    trim(c.memo) as memo,
    trim(c.Receipt) as Receipt,
    trim(c.Location) as Location,
    c.Description_Date,
    trim(c.Card_No) as Card_No,
    trim(c.From) as From,
    trim(c.To) as To,
    a.amount,
    a.line_number,    
    a.primary_key,
    current_date,
    current_time,
    'ING_billsbillsbills' as Account
FROM {{ source('personalfinance_dagster', 'ING_BillsBillsBills_Transactions') }} as a
left join cleaned_memo_data as c
on a.primary_key = c.primary_key