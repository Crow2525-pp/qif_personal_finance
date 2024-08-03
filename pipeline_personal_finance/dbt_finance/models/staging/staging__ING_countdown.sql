WITH cleaned_memo_data AS (
    SELECT
        a.primary_key,
        a.payee AS memo,
        r.receipt,
        l.location,
        d.description_date,
        cn.card_no,
        f.sender,
        t.recepient,
        regexp_split_to_array(a.payee, ' - ') AS split_memo
    FROM
        {{ source('personalfinance_dagster', 'ING_Countdown_Transactions') }} AS a
    LEFT JOIN
        LATERAL (
            SELECT (regexp_matches(a.payee, 'Receipt (\d+)'))[1] AS receipt
        ) AS r
        ON true
    LEFT JOIN
        LATERAL (
            SELECT
                (regexp_matches(a.payee, 'In ([A-Za-z\s]+) Date'))[
                    1
                ] AS location
        ) AS l
        ON true
    LEFT JOIN
        LATERAL (
            SELECT
                (regexp_matches(a.payee, 'Date (\d{2} [A-Za-z]{3} \d{4})'))[
                    1
                ] AS description_date
        ) AS d
        ON true
    LEFT JOIN
        LATERAL (
            SELECT (regexp_matches(a.payee, 'Card ([\dx]+)$'))[1] AS card_no
        ) AS cn
        ON true
    LEFT JOIN
        LATERAL (
            SELECT (regexp_matches(a.payee, 'From ([A-Za-z\s]+)$'))[1] AS sender
        ) AS f
        ON true
    LEFT JOIN
        LATERAL (
            SELECT (regexp_matches(a.payee, 'To ([A-Za-z\s]+)$'))[1] AS recepient
        ) AS t
        ON true
)

SELECT
    c.receipt,
    c.description_date,
    cast(a.amount AS float) AS amount,
    a.line_number,
    a.primary_key,
    'ING_countdown' AS account,
    date_trunc('day', a.date) AS date,
    coalesce(trim((c.split_memo)[1]), null) AS transaction_description,
    coalesce(trim((c.split_memo)[2]), null) AS transaction_type,
    trim(c.memo) AS memo,
    trim(c.location) AS location,
    trim(c.card_no) AS card_no,
    trim(c.sender) AS sender,
    trim(c.recepient) AS recepient,
    current_date,
    current_time
FROM {{ source('personalfinance_dagster', 'ING_Countdown_Transactions') }} AS a
LEFT JOIN cleaned_memo_data AS c
    ON a.primary_key = c.primary_key
