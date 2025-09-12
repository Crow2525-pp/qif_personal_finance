SELECT 
    *,
    running_balance AS unadjusted_balance
FROM {{ ref('int_account_balances') }}
