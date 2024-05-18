WITH adjusted_balance AS (
    {{ calculate_adjusted_balance(ref('staging__Adelaide_Offset')) }})

SELECT
    *
FROM adjusted_balance
