{%
  set enforce_contract = target.type != 'duckdb'
%}
{{
  config(
    materialized='incremental',
    contract={'enforced': enforce_contract},
    constraints=[] if not enforce_contract else none,
    unique_key=['account_key', 'balance_date'],
    on_schema_change='append_new_columns',
    indexes=[
      {'columns': ['balance_date'], 'unique': false},
      {'columns': ['account_key', 'balance_date'], 'unique': true}
    ],
    post_hook=[
      "{{ create_fk_if_not_exists(this, 'account_key', ref('dim_accounts'), 'account_key', 'fk_daily_balances_account') }}"
    ]
  )
}}

WITH daily_account_activity AS (
  SELECT 
    account_key,
    transaction_date AS balance_date,
    SUM(transaction_amount) AS daily_net_amount,
    COUNT(*) AS daily_transaction_count,
    CAST(SUM(CASE WHEN transaction_direction = 'Debit' THEN transaction_amount_abs ELSE 0 END) AS DECIMAL(15,2)) AS total_debits,
    CAST(SUM(CASE WHEN transaction_direction = 'Credit' THEN transaction_amount_abs ELSE 0 END) AS DECIMAL(15,2)) AS total_credits,
    MAX(account_balance) AS end_of_day_balance -- Last balance of the day
  FROM {{ ref('fct_transactions') }}
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
  FROM {{ ref('dim_accounts') }} da
  CROSS JOIN {{ ref('dim_date_calendar') }} dc
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
    CAST(COALESCE(daa.total_debits, 0) AS DECIMAL(15,2)) AS total_debits,
    CAST(COALESCE(daa.total_credits, 0) AS DECIMAL(15,2)) AS total_credits,
    daa.end_of_day_balance
  FROM date_spine ds
  LEFT JOIN daily_account_activity daa
    ON ds.account_key = daa.account_key 
    AND ds.balance_date = daa.balance_date
),

-- Fill forward balances for days with no transactions
final_balances_base AS (
  SELECT 
    account_key,
    balance_date,
    
    -- Use last known balance if no transactions on this day
    CAST(COALESCE(
      end_of_day_balance,
      LAG(end_of_day_balance) OVER (
        PARTITION BY account_key
        ORDER BY balance_date
      )
    ) AS DECIMAL(15,2)) AS daily_balance,
    
    -- Aggregates
    CAST(daily_transaction_count AS BIGINT) AS transaction_count,
    total_debits,
    total_credits,
    
    -- Flags
    (EXTRACT(DOW FROM balance_date) IN (0, 6)) AS is_weekend,
    (balance_date = (date_trunc('month', balance_date) + interval '1 month' - interval '1 day')::date) AS is_month_end,
    
    -- Metadata
    CAST(CURRENT_TIMESTAMP AS TIMESTAMP) AS created_at
    
  FROM daily_balances_with_gaps
),

final_balances AS (
  SELECT
    *,
    CAST(COALESCE(
      daily_balance - LAG(daily_balance) OVER (
        PARTITION BY account_key
        ORDER BY balance_date
      ), 0
    ) AS DECIMAL(15,2)) AS balance_change
  FROM final_balances_base
),

final_with_account AS (
  SELECT
    -- keys
    {{ dbt_utils.generate_surrogate_key(['fb.account_key', 'fb.balance_date']) }} AS balance_key,
    fb.balance_date,
    fb.account_key,
    da.account_name,
    
    -- metrics
    fb.daily_balance,
    fb.balance_change,
    fb.transaction_count,
    fb.total_debits,
    fb.total_credits,
    fb.is_weekend,
    fb.is_month_end,
    fb.created_at
  FROM final_balances fb
  JOIN {{ ref('dim_accounts') }} da
    ON fb.account_key = da.account_key
)

SELECT *
FROM final_with_account
WHERE daily_balance IS NOT NULL -- Only include dates where we have balance data
