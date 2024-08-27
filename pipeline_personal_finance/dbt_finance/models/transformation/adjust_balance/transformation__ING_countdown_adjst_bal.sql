WITH adjusted_balance AS (
    {{ calculate_adjusted_balance('staging__ING_countdown') }})

SELECT
    *
FROM adjusted_balance

