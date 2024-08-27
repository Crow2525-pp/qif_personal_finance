WITH categorised AS (
    {{ categorise_transactions('staging__ING_countdown') }})

SELECT
    *
FROM categorised
