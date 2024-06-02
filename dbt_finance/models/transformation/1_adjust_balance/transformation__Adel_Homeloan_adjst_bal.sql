WITH adjusted_balance AS (
    {{ calculate_adjusted_balance('staging__Adelaide_Homeloan') }})

SELECT
    *
FROM adjusted_balance
