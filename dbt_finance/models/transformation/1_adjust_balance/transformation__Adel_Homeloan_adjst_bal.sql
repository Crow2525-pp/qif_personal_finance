WITH adjusted_balance AS (
    {{ calculate_adjusted_balance(ref('staging__Adelaide_Homeloan')) }})

SELECT
    *
FROM adjusted_balance
