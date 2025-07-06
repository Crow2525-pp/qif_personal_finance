
-- Calculates adjusted balances for the Adelaide Homeloan account using known values.
-- Depends on: staging__Adelaide_Homeloan, calculate_adjusted_balance macro.
with adjusted_balance as (
    {{ calculate_adjusted_balance('staging__Adelaide_Homeloan') }})

select
    *
from adjusted_balance
