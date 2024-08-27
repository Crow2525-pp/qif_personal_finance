WITH categorised AS (
    {{ categorise_transactions('staging__billsbillsbills') }})

SELECT
    *
FROM categorised
