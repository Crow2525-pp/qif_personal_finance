WITH adjusted_balance AS (
    {{ calculate_adjusted_balance('stg_ing_billsbillsbills') }})

SELECT
    *
FROM adjusted_balance
