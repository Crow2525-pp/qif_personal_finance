{{
  config(
    materialized='incremental',
    unique_key=['account_key', 'balance_date'],
    on_schema_change='fail',
    indexes=[
      {'columns': ['balance_date'], 'unique': false},
      {'columns': ['account_key', 'balance_date'], 'unique': true}
    ]
  )
}}

WITH daily_account_activity AS (
  SELECT 
    account_key,
    transaction_date AS balance_date,
    SUM(transaction_amount) AS daily_net_amount,
    COUNT(*) AS daily_transaction_count,
    MAX(account_balance) AS end_of_day_balance -- Last balance of the day
  FROM {{ ref('fact_transactions_enhanced') }}
  {% if is_incremental() %}
    WHERE transaction_date > (SELECT MAX(balance_date) FROM {{ this }})
  {% endif %}
  GROUP BY account_key, transaction_date
),

-- Generate date spine to ensure we have records for all dates
date_spine AS (
  SELECT 
    da.account_key,
    dc.date AS balance_date,
    da.account_start_date,
    da.account_last_transaction_date
  FROM {{ ref('dim_accounts_enhanced') }} da
  CROSS JOIN {{ ref('date_calendar') }} dc
  WHERE dc.date >= da.account_start_date
    AND dc.date <= CURRENT_DATE
    {% if is_incremental() %}
      AND dc.date > (SELECT MAX(balance_date) FROM {{ this }})
    {% endif %}
),

daily_balances_with_gaps AS (
  SELECT 
    ds.account_key,
    ds.balance_date,
    COALESCE(daa.daily_net_amount, 0) AS daily_net_amount,
    COALESCE(daa.daily_transaction_count, 0) AS daily_transaction_count,
    daa.end_of_day_balance
  FROM date_spine ds
  LEFT JOIN daily_account_activity daa
    ON ds.account_key = daa.account_key 
    AND ds.balance_date = daa.balance_date
),

-- Fill forward balances for days with no transactions
final_balances AS (
  SELECT 
    account_key,
    balance_date,
    daily_net_amount,
    daily_transaction_count,
    
    -- Use last known balance if no transactions on this day
    COALESCE(
      end_of_day_balance,
      LAG(end_of_day_balance) OVER (
        PARTITION BY account_key 
        ORDER BY balance_date
      )
    ) AS end_of_day_balance,
    
    -- Additional metrics
    SUM(daily_net_amount) OVER (
      PARTITION BY account_key 
      ORDER BY balance_date 
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_net_amount,
    
    -- Metadata
    CURRENT_TIMESTAMP AS created_at
    
  FROM daily_balances_with_gaps
)

SELECT * FROM final_balances
WHERE end_of_day_balance IS NOT NULL -- Only include dates where we have balance data