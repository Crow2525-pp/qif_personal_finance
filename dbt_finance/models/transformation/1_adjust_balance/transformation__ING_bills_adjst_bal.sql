WITH adjusted_balance AS (
    {{ calculate_adjusted_balance(ref('staging__ING_billsbillsbills')) }})

SELECT
    *
FROM adjusted_balance
