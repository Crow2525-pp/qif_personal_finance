WITH adjusted_balance AS (
    {{ calculate_adjusted_balance('stg_adelaide_offset') }})

SELECT
    *
FROM adjusted_balance
