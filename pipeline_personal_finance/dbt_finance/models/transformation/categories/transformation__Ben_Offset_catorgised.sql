WITH categorised AS (
    {{ categorise_transactions('staging__Bendigo_Offset') }})

SELECT
    *
FROM categorised
