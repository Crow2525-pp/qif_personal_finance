{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['account_name', 'transaction_date'], 'unique': false},
      {'columns': ['primary_key'], 'unique': false}
    ]
  )
}}

WITH all_staging_accounts AS (
  {{ dbt_utils.union_relations(
    relations=[
      ref('staging__Adelaide_Homeloan'),
      ref('staging__Adelaide_Offset'),
      ref('staging__Bendigo_Homeloan'),
      ref('staging__Bendigo_Offset'),
      ref('staging__ING_billsbillsbills'),
      ref('staging__ING_countdown')
    ]
  ) }}
),

-- Remove any potential duplicates from union
deduplicated_accounts AS (
  SELECT DISTINCT * FROM all_staging_accounts
),

transactions_with_running_balance AS (
  SELECT 
    {{ dbt_utils.star(from=ref('staging__Adelaide_Homeloan')) }},
    CAST(SUM(transaction_amount) OVER (
      PARTITION BY account_name
      ORDER BY transaction_date ASC, line_number ASC
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS DECIMAL(14,2)) AS running_balance
  FROM deduplicated_accounts
),

known_balance_points AS (
  SELECT 
    CAST(account_balance AS DECIMAL(14,2)) AS known_balance,
    specific_date,
    LOWER(account_name) AS account_name
  FROM {{ ref('known_values') }}
),

balance_adjustments AS (
  SELECT 
    t.account_name,
    (t.running_balance - k.known_balance) AS adjustment_amount,
    k.specific_date AS adjustment_date
  FROM transactions_with_running_balance t
  INNER JOIN known_balance_points k
    ON LOWER(t.account_name) = k.account_name
    AND t.transaction_date = k.specific_date
),

final_balances AS (
  SELECT 
    t.*,
    t.running_balance - COALESCE(adj.adjustment_amount, 0) AS adjusted_transaction_balance,
    adj.adjustment_amount,
    adj.adjustment_date
  FROM transactions_with_running_balance t
  LEFT JOIN balance_adjustments adj
    ON t.account_name = adj.account_name
)

SELECT * FROM final_balances