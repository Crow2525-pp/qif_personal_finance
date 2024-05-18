WITH adjusted_balance AS (
    {{ calculate_adjusted_balance(ref('staging__ING_countdown')) }})

SELECT
    *
FROM adjusted_balance

