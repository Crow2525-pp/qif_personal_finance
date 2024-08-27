WITH categorised AS (
    {{ categorise_transactions('staging__Adelaide_Offset') }})

SELECT
    *
FROM categorised
