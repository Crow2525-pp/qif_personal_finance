WITH adjusted_balance AS (
    {{ calculate_adjusted_balance('staging__ING_billsbillsbills') }})

SELECT
    *
FROM adjusted_balance
