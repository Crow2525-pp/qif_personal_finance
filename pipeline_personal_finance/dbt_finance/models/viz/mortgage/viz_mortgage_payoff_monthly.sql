{{
  config(
    materialized='view'
  )
}}

-- Monthly mortgage and offset balances derived directly from landing transactions.
-- Produces one row per calendar month with mortgage balance, offset balance,
-- and net mortgage exposure (mortgage minus offset).

WITH homeloan_txn AS (
  SELECT
    CAST(date AS date)             AS txn_date,
    CAST(amount AS numeric)        AS amount
  FROM {{ source('personalfinance_dagster', 'Bendigo_Homeloan_Transactions') }}
),

homeloan_running AS (
  SELECT
    txn_date,
    SUM(amount) OVER (
      ORDER BY txn_date, amount
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS homeloan_balance
  FROM homeloan_txn
),

homeloan_monthly AS (
  SELECT DISTINCT ON (DATE_TRUNC('month', txn_date))
    DATE_TRUNC('month', txn_date)::date AS month_start,
    ABS(homeloan_balance)               AS mortgage_balance
  FROM homeloan_running
  ORDER BY DATE_TRUNC('month', txn_date), txn_date DESC
),

offset_txn AS (
  SELECT
    CAST(date AS date)             AS txn_date,
    CAST(amount AS numeric)        AS amount
  FROM {{ source('personalfinance_dagster', 'Bendigo_Offset_Transactions') }}
),

offset_running AS (
  SELECT
    txn_date,
    SUM(amount) OVER (
      ORDER BY txn_date, amount
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS offset_balance
  FROM offset_txn
),

offset_monthly AS (
  SELECT DISTINCT ON (DATE_TRUNC('month', txn_date))
    DATE_TRUNC('month', txn_date)::date AS month_start,
    offset_balance
  FROM offset_running
  ORDER BY DATE_TRUNC('month', txn_date), txn_date DESC
),

combined AS (
  SELECT
    COALESCE(h.month_start, o.month_start) AS month_start,
    h.mortgage_balance,
    o.offset_balance,
    CASE
      WHEN h.mortgage_balance IS NOT NULL AND o.offset_balance IS NOT NULL
      THEN h.mortgage_balance - o.offset_balance
      ELSE NULL
    END AS net_mortgage_exposure
  FROM homeloan_monthly h
  FULL JOIN offset_monthly o
    ON o.month_start = h.month_start
),

latest_dates AS (
  SELECT
    (SELECT MAX(txn_date) FROM homeloan_txn) AS homeloan_latest_date,
    (SELECT MAX(txn_date) FROM offset_txn)   AS offset_latest_date
)

SELECT
  c.month_start,
  c.mortgage_balance,
  c.offset_balance,
  c.net_mortgage_exposure,
  ld.homeloan_latest_date,
  ld.offset_latest_date,
  CASE
    WHEN DATE_TRUNC('month', LEAST(ld.homeloan_latest_date, ld.offset_latest_date))
         < DATE_TRUNC('month', CURRENT_DATE)
    THEN 'Using previous available month (current month incomplete for homeloan/offset)'
    ELSE 'Current month available'
  END AS data_note,
  NOW() AT TIME ZONE 'Australia/Melbourne' AS report_generated_at
FROM combined c
CROSS JOIN latest_dates ld
