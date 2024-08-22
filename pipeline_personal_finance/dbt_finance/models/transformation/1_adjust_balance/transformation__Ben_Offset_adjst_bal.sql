WITH adjusted_balance AS (
    {{ calculate_adjusted_balance('staging__Bendigo_Offset') }})

SELECT
    *
FROM adjusted_balance
