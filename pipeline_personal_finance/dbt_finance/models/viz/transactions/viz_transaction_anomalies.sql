{{ config(materialized='view') }}

-- This view identifies unusually high transactions compared to 12-month baseline
-- It flags transactions that deviate significantly from historical patterns for the same merchant/category

WITH transaction_baseline AS (
  SELECT
    -- Transaction details
    ft.transaction_date,
    TO_CHAR(ft.transaction_date, 'YYYY-MM') AS year_month,
    ft.transaction_amount,
    ABS(ft.transaction_amount) AS amount_abs,

    -- Account context
    da.account_name,
    da.bank_name,
    da.account_type,

    -- Category context
    dc.category AS category_name,
    dc.level_1_category,
    dc.level_2_subcategory,
    dc.store AS merchant_name,

    -- Transaction attributes
    ft.transaction_memo,
    ft.transaction_description,
    ft.transaction_type,
    ft.sender,
    ft.recipient,

    -- Flags
    ft.is_income_transaction,
    ft.is_internal_transfer,
    ft.is_financial_service,

    -- Compute 12-month rolling statistics for same merchant (time-based window)
    AVG(ABS(ft.transaction_amount)) OVER (
      PARTITION BY UPPER(COALESCE(dc.store, ft.transaction_memo))
      ORDER BY ft.transaction_date
      RANGE BETWEEN INTERVAL '12 months' PRECEDING AND CURRENT ROW
    ) AS merchant_12m_avg,

    STDDEV_POP(ABS(ft.transaction_amount)) OVER (
      PARTITION BY UPPER(COALESCE(dc.store, ft.transaction_memo))
      ORDER BY ft.transaction_date
      RANGE BETWEEN INTERVAL '12 months' PRECEDING AND CURRENT ROW
    ) AS merchant_12m_stddev,

    MAX(ABS(ft.transaction_amount)) OVER (
      PARTITION BY UPPER(COALESCE(dc.store, ft.transaction_memo))
      ORDER BY ft.transaction_date
      RANGE BETWEEN INTERVAL '12 months' PRECEDING AND CURRENT ROW
    ) AS merchant_12m_max,

    COUNT(*) OVER (
      PARTITION BY UPPER(COALESCE(dc.store, ft.transaction_memo))
      ORDER BY ft.transaction_date
      RANGE BETWEEN INTERVAL '12 months' PRECEDING AND CURRENT ROW
    ) AS merchant_12m_count

  FROM {{ ref('fct_transactions') }} ft
  LEFT JOIN {{ ref('dim_accounts') }} da
    ON ft.account_key = da.account_key
  LEFT JOIN {{ ref('dim_categories') }} dc
    ON ft.category_key = dc.category_key

  WHERE ft.transaction_amount < 0  -- Only expenses
    AND NOT COALESCE(ft.is_internal_transfer, FALSE)  -- Exclude internal transfers
    AND NOT COALESCE(ft.is_financial_service, FALSE)  -- Exclude financial services
    AND NOT COALESCE(ft.is_income_transaction, FALSE)  -- Exclude income
),

-- Calculate anomaly scores
with_anomaly_flags AS (
  SELECT
    *,

    -- Flag if this transaction is >50% higher than merchant 12-month average (or 2+ std devs)
    CASE
      WHEN merchant_12m_count >= 3 AND merchant_12m_stddev IS NOT NULL
        AND amount_abs > (merchant_12m_avg + (2 * merchant_12m_stddev))
      THEN TRUE
      WHEN merchant_12m_count >= 3 AND merchant_12m_avg > 0
        AND amount_abs > (merchant_12m_avg * 1.5)
      THEN TRUE
      ELSE FALSE
    END AS is_anomaly,

    -- Calculate variance percentage for anomalous transactions
    CASE
      WHEN merchant_12m_avg > 0
      THEN ROUND(((amount_abs - merchant_12m_avg) / merchant_12m_avg) * 100, 1)
      ELSE NULL
    END AS variance_from_avg_pct,

    -- Anomaly severity: how many standard deviations away
    CASE
      WHEN merchant_12m_stddev IS NOT NULL AND merchant_12m_stddev > 0
      THEN ROUND((amount_abs - merchant_12m_avg) / merchant_12m_stddev, 2)
      ELSE NULL
    END AS stddev_multiplier

  FROM transaction_baseline
)

SELECT
  transaction_date,
  year_month,
  TO_DATE(year_month || '-01', 'YYYY-MM-DD')::timestamp AS time,

  -- Transaction amount
  transaction_amount,
  amount_abs,

  -- Account context
  account_name,
  bank_name,
  account_type,

  -- Merchant/Category context
  COALESCE(merchant_name, 'Unknown Merchant') AS merchant_name,
  category_name,
  level_1_category,
  level_2_subcategory,

  -- Transaction details
  transaction_memo,
  transaction_description,
  transaction_type,
  sender,
  recipient,

  -- Baseline statistics
  ROUND(merchant_12m_avg::numeric, 2) AS merchant_12m_avg,
  ROUND(merchant_12m_stddev::numeric, 2) AS merchant_12m_stddev,
  merchant_12m_max,
  merchant_12m_count,

  -- Anomaly flags
  is_anomaly,
  variance_from_avg_pct,
  stddev_multiplier,

  -- Anomaly severity label
  CASE
    WHEN NOT is_anomaly THEN 'Normal'
    WHEN variance_from_avg_pct >= 150 THEN '🔴 Severe (>150% above avg)'
    WHEN variance_from_avg_pct >= 100 THEN '🟠 High (100-150% above avg)'
    WHEN variance_from_avg_pct >= 50 THEN '🟡 Moderate (50-100% above avg)'
    ELSE '🟢 Minor (under 50% above avg)'
  END AS anomaly_severity_label

FROM with_anomaly_flags
WHERE is_anomaly = TRUE  -- Only return anomalies
  OR transaction_date >= CURRENT_DATE - INTERVAL '3 months'  -- Or recent transactions

ORDER BY
  is_anomaly DESC,
  variance_from_avg_pct DESC,
  transaction_date DESC
