WITH adjusted_balance AS (
    {{ calculate_adjusted_balance(ref('staging__Bendigo_Bank_Homeloan')) }})

SELECT
    *
FROM adjusted_balance
