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
    da.is_liability,
    eom.daily_balance
  FROM eom
  JOIN {{ ref('dim_accounts') }} da
    ON eom.account_key = da.account_key
)

SELECT 
  month_date AS date,
  SUM(CASE WHEN NOT is_liability THEN daily_balance ELSE 0 END)                     AS total_assets,
  SUM(CASE WHEN is_liability THEN ABS(daily_balance) ELSE 0 END)                   AS total_liabilities,
  SUM(CASE WHEN NOT is_liability THEN daily_balance ELSE -ABS(daily_balance) END)  AS net_worth
FROM joined
GROUP BY month_date
ORDER BY date
