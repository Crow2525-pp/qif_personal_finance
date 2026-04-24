WITH adjusted_balance AS (
    {{ calculate_adjusted_balance('stg_bendigo_homeloan') }})

SELECT
    *
FROM adjusted_balance
