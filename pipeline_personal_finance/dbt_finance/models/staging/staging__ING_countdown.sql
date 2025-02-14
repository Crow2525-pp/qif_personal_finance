WITH parsed_memo_data AS (
    SELECT
        transactions.primary_key,
        transactions.payee AS memo,
        regexp_split_to_array(transactions.payee, ' - ') AS split_memo,

        -- Extract relevant details using regex pattern matching
        receipt_data.receipt,
        location_data.location,
        description_date_data.description_date,
        card_number_data.card_no,
        sender_data.sender,
        recipient_data.recipient

    FROM {{ source('personalfinance_dagster', 'ING_BillsBillsBills_Transactions') }} transactions

    -- Extract receipt number
    LEFT JOIN LATERAL (
        SELECT (regexp_matches(transactions.payee, 'Receipt (\d+)'))[1] AS receipt
    ) receipt_data ON transactions.payee ~ 'Receipt (\d+)'

    -- Extract location information
    LEFT JOIN LATERAL (
        SELECT (regexp_matches(transactions.payee, 'In ([A-Za-z\s]+) Date'))[1] AS location
    ) location_data ON transactions.payee ~ 'In ([A-Za-z\s]+) Date'

    -- Extract date information
    LEFT JOIN LATERAL (
        SELECT (regexp_matches(transactions.payee, 'Date (\d{2} [A-Za-z]{3} \d{4})'))[1] AS description_date
    ) description_date_data ON transactions.payee ~ 'Date (\d{2} [A-Za-z]{3} \d{4})'

    -- Extract card number
    LEFT JOIN LATERAL (
        SELECT (regexp_matches(transactions.payee, 'Card ([\dx]+)$'))[1] AS card_no
    ) card_number_data ON transactions.payee ~ 'Card ([\dx]+)$'

    -- Extract sender name
    LEFT JOIN LATERAL (
        SELECT (regexp_matches(transactions.payee, 'From ([A-Za-z\s]+)$'))[1] AS sender
    ) sender_data ON transactions.payee ~ 'From ([A-Za-z\s]+)$'

    -- Extract recipient name
    LEFT JOIN LATERAL (
        SELECT (regexp_matches(transactions.payee, 'To ([A-Za-z\s]+)$'))[1] AS recipient
    ) recipient_data ON transactions.payee ~ 'To ([A-Za-z\s]+)$'
)

SELECT
    -- Normalize the date column
    CAST(DATE_TRUNC('day', transactions.date) AS DATE) AS transaction_date,

    -- Extract transaction details from memo
    COALESCE(TRIM((parsed_memo.split_memo)[1]), NULL) AS transaction_description,
    COALESCE(TRIM((parsed_memo.split_memo)[2]), NULL) AS transaction_type,
    TRIM(parsed_memo.memo) AS memo,

    -- Extracted metadata from regex matches
    TRIM(parsed_memo.receipt) AS receipt,
    TRIM(parsed_memo.location) AS location,
    parsed_memo.description_date,
    TRIM(parsed_memo.card_no) AS card_no,
    TRIM(parsed_memo.sender) AS sender,
    TRIM(parsed_memo.recipient) AS recipient,

    -- Financial details
    CAST(transactions.amount AS FLOAT) AS transaction_amount,
    transactions.line_number,
    transactions.primary_key,

    -- ETL metadata
    CURRENT_DATE AS etl_date,
    CURRENT_TIME AS etl_time,
    'ing_billsbillsbills' AS account_name

FROM {{ source('personalfinance_dagster', 'ING_BillsBillsBills_Transactions') }} transactions
LEFT JOIN parsed_memo_data AS parsed_memo
    ON transactions.primary_key = parsed_memo.primary_key
