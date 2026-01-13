WITH eom AS (
  SELECT 
    fdb.balance_date::date AS month_date,
    fdb.account_key,
    fdb.daily_balance
  FROM {{ ref('fct_daily_balances') }} fdb
  WHERE fdb.is_month_end = TRUE
    AND fdb.balance_date >= (date_trunc('month', current_date) - interval '23 months')::date
),

joined AS (
  SELECT 
    eom.month_date,
    da.account_name,
    da.bank_name,
    da.account_type,
    da.is_liability,
    eom.daily_balance AS balance
  FROM eom
  JOIN {{ ref('dim_accounts') }} da
    ON eom.account_key = da.account_key
)

SELECT 
  month_date AS date,
  account_name,
  bank_name,
  account_type,
  is_liability,
  balance
FROM joined
ORDER BY date, account_name
