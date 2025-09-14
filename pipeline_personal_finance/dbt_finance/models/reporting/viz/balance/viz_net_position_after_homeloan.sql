-- Net Position after offsetting Home Loan with Offset (and other liquid assets if desired)
-- Compute month-end balances from the daily fact, join account flags, then aggregate
-- Use the last available balance for each month to handle missing month-end dates

WITH monthly_balances AS (
  SELECT
    DATE_TRUNC('month', fb.balance_date)::date AS year_month,
    fb.account_key,
    fb.balance_date,
    fb.daily_balance,
    ROW_NUMBER() OVER (
      PARTITION BY DATE_TRUNC('month', fb.balance_date)::date, fb.account_key
      ORDER BY fb.balance_date DESC
    ) AS rn
  FROM {{ ref('fct_daily_balances') }} fb
),

eom AS (
  SELECT
    year_month,
    account_key,
    daily_balance AS month_end_balance
  FROM monthly_balances
  WHERE rn = 1
),

filtered_accounts AS (
  SELECT 
    eom.year_month,
    eom.account_key,
    da.account_type,
    da.is_mortgage,
    da.is_liquid_asset,
    eom.month_end_balance
  FROM eom
  JOIN {{ ref('dim_accounts_enhanced') }} da
    ON eom.account_key = da.account_key
  -- Keep only mortgage and offset accounts for the net position after home loan
  WHERE da.account_type IN ('Home Loan', 'Offset')
),

net_by_month AS (
  SELECT 
    year_month,
    SUM(month_end_balance) AS net_position
  FROM filtered_accounts
  GROUP BY year_month
)

SELECT 
  year_month,
  net_position
FROM net_by_month
ORDER BY year_month
