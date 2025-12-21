{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['merchant_pattern'], 'unique': false},
      {'columns': ['recurrence_type'], 'unique': false},
      {'columns': ['category'], 'unique': false}
    ]
  )
}}

-- Identifies and analyzes recurring transactions to help track subscriptions,
-- regular bills, and predictable expenses

WITH transaction_base AS (
  SELECT
    ft.transaction_date,
    ft.transaction_description,
    ft.transaction_memo,
    ft.transaction_amount,
    dc.level_1_category AS category,
    dc.level_2_subcategory AS subcategory,
    da.account_name,
    ft.transaction_year,
    ft.transaction_month
  FROM {{ ref('fct_transactions_enhanced') }} ft
  LEFT JOIN {{ ref('dim_categories_enhanced') }} dc
    ON ft.category_key = dc.category_key
  LEFT JOIN {{ ref('dim_accounts_enhanced') }} da
    ON ft.account_key = da.account_key
  WHERE NOT COALESCE(ft.is_internal_transfer, FALSE)
    AND ft.transaction_amount < 0  -- Only expenses
),

-- Normalize merchant names to identify recurring patterns
merchant_normalized AS (
  SELECT
    *,
    -- Clean up transaction description to group similar merchants
    REGEXP_REPLACE(
      UPPER(COALESCE(transaction_description, transaction_memo)),
      '[0-9]+|[^A-Z ]',
      '',
      'g'
    ) AS merchant_pattern
  FROM transaction_base
),

-- Count occurrences by merchant and calculate statistics
merchant_frequency AS (
  SELECT
    merchant_pattern,
    category,
    subcategory,
    account_name,
    COUNT(*) AS transaction_count,
    COUNT(DISTINCT transaction_year || '-' || LPAD(transaction_month::TEXT, 2, '0')) AS months_appeared,
    MIN(transaction_date) AS first_transaction_date,
    MAX(transaction_date) AS last_transaction_date,
    AVG(ABS(transaction_amount)) AS avg_amount,
    STDDEV(ABS(transaction_amount)) AS amount_stddev,
    MIN(ABS(transaction_amount)) AS min_amount,
    MAX(ABS(transaction_amount)) AS max_amount,
    SUM(ABS(transaction_amount)) AS total_spent
  FROM merchant_normalized
  WHERE LENGTH(merchant_pattern) > 3  -- Filter out very short patterns
  GROUP BY merchant_pattern, category, subcategory, account_name
  HAVING COUNT(*) >= 3  -- Must appear at least 3 times to be considered recurring
),

-- Classify recurrence patterns
recurrence_classification_base AS (
  SELECT
    *,
    -- Determine likely recurrence type based on frequency
    CASE
      WHEN transaction_count >= months_appeared * 0.9
           AND months_appeared >= 3 THEN 'Monthly'
      WHEN transaction_count >= (months_appeared / 3.0) * 0.8
           AND months_appeared >= 6 THEN 'Quarterly'
      WHEN transaction_count >= (months_appeared / 6.0) * 0.8
           AND months_appeared >= 12 THEN 'Semi-Annual'
      WHEN transaction_count >= (months_appeared / 12.0) * 0.8
           AND months_appeared >= 24 THEN 'Annual'
      WHEN months_appeared >= 6 THEN 'Irregular Recurring'
      ELSE 'One-time/Rare'
    END AS recurrence_type,

    -- Calculate consistency score (0-100)
    CASE
      WHEN avg_amount > 0 THEN
        LEAST(100, GREATEST(0,
          100 - (COALESCE(amount_stddev, 0) / avg_amount * 100)
        ))
      ELSE 0
    END AS amount_consistency_score,

    -- Days between first and last transaction
    (last_transaction_date - first_transaction_date) AS days_active,

    -- Estimated monthly cost
    CASE
      WHEN months_appeared > 0 THEN total_spent / months_appeared
      ELSE 0
    END AS estimated_monthly_cost,

    -- Days since last transaction
    (CURRENT_DATE - last_transaction_date) AS days_since_last_transaction

  FROM merchant_frequency
),

recurrence_classification AS (
  SELECT
    *
  FROM recurrence_classification_base
),

-- Add additional insights and rankings
final_analysis AS (
  SELECT
    merchant_pattern,
    category,
    subcategory,
    account_name,
    recurrence_type,
    transaction_count,
    months_appeared,
    days_active,
    first_transaction_date,
    last_transaction_date,

    -- Amount statistics
    ROUND(avg_amount, 2) AS average_transaction_amount,
    ROUND(amount_stddev, 2) AS amount_std_deviation,
    ROUND(min_amount, 2) AS minimum_amount,
    ROUND(max_amount, 2) AS maximum_amount,
    ROUND(total_spent, 2) AS total_lifetime_spend,
    ROUND(estimated_monthly_cost, 2) AS estimated_monthly_cost,
    ROUND(estimated_monthly_cost * 12, 2) AS estimated_annual_cost,

    -- Consistency and reliability metrics
    ROUND(amount_consistency_score, 1) AS consistency_score,

    -- Is this still active? (transaction in last 60 days)
    (last_transaction_date >= CURRENT_DATE - INTERVAL '60 days') AS is_currently_active,

    -- Risk flags
    CASE
      WHEN recurrence_type = 'Monthly'
           AND days_since_last_transaction > 45 THEN TRUE
      WHEN recurrence_type = 'Quarterly'
           AND days_since_last_transaction > 120 THEN TRUE
      WHEN recurrence_type = 'Annual'
           AND days_since_last_transaction > 400 THEN TRUE
      ELSE FALSE
    END AS possibly_cancelled,

    -- Rankings
    RANK() OVER (ORDER BY estimated_monthly_cost DESC) AS cost_rank,
    RANK() OVER (PARTITION BY category ORDER BY estimated_monthly_cost DESC) AS cost_rank_within_category,

    -- Subscription likelihood score (0-100)
    CASE
      WHEN category IN ('Entertainment', 'Technology', 'Health & Beauty')
           AND recurrence_type = 'Monthly'
           AND amount_consistency_score > 80 THEN 95
      WHEN recurrence_type = 'Monthly'
           AND amount_consistency_score > 90 THEN 85
      WHEN recurrence_type = 'Monthly'
           AND amount_consistency_score > 70 THEN 75
      WHEN recurrence_type IN ('Quarterly', 'Annual')
           AND amount_consistency_score > 80 THEN 70
      WHEN recurrence_type = 'Monthly' THEN 60
      ELSE 30
    END AS subscription_likelihood_score,

    CURRENT_TIMESTAMP AS report_generated_at

  FROM recurrence_classification
  WHERE recurrence_type != 'One-time/Rare'  -- Filter out non-recurring items
)

SELECT * FROM final_analysis
ORDER BY estimated_monthly_cost DESC
