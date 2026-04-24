
-- Calculates adjusted balances for the Adelaide Homeloan account using known values.
-- Depends on: stg_adelaide_homeloan, calculate_adjusted_balance macro.
with adjusted_balance as (
    {{ calculate_adjusted_balance('stg_adelaide_homeloan') }})

select
    *
from adjusted_balance
