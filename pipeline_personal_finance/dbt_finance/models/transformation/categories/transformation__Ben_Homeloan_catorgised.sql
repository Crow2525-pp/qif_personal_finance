WITH categorised AS (
    {{ categorise_transactions('staging__Bendigo_Homeloan') }})

SELECT
    *
FROM categorised
