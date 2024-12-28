with adjusted_balance as (
    {{ calculate_adjusted_balance('staging__Adelaide_Homeloan') }})

select
    *
from adjusted_balance
