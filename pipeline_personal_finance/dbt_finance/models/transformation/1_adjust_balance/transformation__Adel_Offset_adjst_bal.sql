WITH adjusted_balance AS (
    {{ calculate_adjusted_balance('staging__Adelaide_Offset') }})

SELECT
    *
FROM adjusted_balance
