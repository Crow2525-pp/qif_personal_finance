WITH categorised AS (
    {{ categorise_transactions('staging__Adelaide_Homeloan') }})

SELECT
    *
FROM categorised
