WITH adjusted_balance AS (
    {{ calculate_adjusted_balance('stg_ing_countdown') }})

SELECT
    *
FROM adjusted_balance

