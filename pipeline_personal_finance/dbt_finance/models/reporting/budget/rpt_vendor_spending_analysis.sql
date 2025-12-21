{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['vendor_name'], 'unique': false},
      {'columns': ['category'], 'unique': false},
      {'columns': ['spending_tier'], 'unique': false}
    ]
  )
}}

-- Analyzes spending patterns by vendor/merchant
-- Identifies top vendors, spending trends, and helps track where money is going

WITH transaction_vendors AS (
  SELECT
    ft.transaction_date,
    ft.transaction_year,
    ft.transaction_month,
    -- Use transaction description as vendor identifier, fallback to memo
    COALESCE(
      NULLIF(TRIM(ft.transaction_description), ''),
      NULLIF(TRIM(ft.transaction_memo), ''),
      'Unknown Vendor'
    ) AS vendor_name,
    dc.level_1_category AS category,
    dc.level_2_subcategory AS subcategory,
    dc.level_3_store AS store,
    da.account_name,
    ABS(ft.transaction_amount) AS transaction_amount
  FROM {{ ref('fct_transactions_enhanced') }} ft
  LEFT JOIN {{ ref('dim_categories_enhanced') }} dc
    ON ft.category_key = dc.category_key
  LEFT JOIN {{ ref('dim_accounts_enhanced') }} da
    ON ft.account_key = da.account_key
  WHERE ft.transaction_amount < 0  -- Only expenses
    AND NOT COALESCE(ft.is_internal_transfer, FALSE)
    AND NOT COALESCE(ft.is_financial_service, FALSE)
),

vendor_aggregates AS (
  SELECT
    vendor_name,
    category,
    subcategory,
    store,

    -- Transaction counts and dates
    COUNT(*) AS total_transactions,
    MIN(transaction_date) AS first_transaction_date,
    MAX(transaction_date) AS last_transaction_date,
    COUNT(DISTINCT transaction_year || '-' || LPAD(transaction_month::TEXT, 2, '0')) AS months_with_transactions,
    COUNT(DISTINCT transaction_year) AS years_active,

    -- Spending metrics
    SUM(transaction_amount) AS total_lifetime_spend,
    AVG(transaction_amount) AS average_transaction_amount,
    STDDEV(transaction_amount) AS transaction_amount_stddev,
    MIN(transaction_amount) AS minimum_transaction,
    MAX(transaction_amount) AS maximum_transaction,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY transaction_amount) AS median_transaction,

    -- Recent activity (last 90 days)
    SUM(CASE
      WHEN transaction_date >= CURRENT_DATE - INTERVAL '90 days' THEN transaction_amount
      ELSE 0
    END) AS spend_last_90_days,

    COUNT(CASE
      WHEN transaction_date >= CURRENT_DATE - INTERVAL '90 days' THEN 1
    END) AS transactions_last_90_days,

    -- Recent activity (last 365 days)
    SUM(CASE
      WHEN transaction_date >= CURRENT_DATE - INTERVAL '365 days' THEN transaction_amount
      ELSE 0
    END) AS spend_last_12_months,

    COUNT(CASE
      WHEN transaction_date >= CURRENT_DATE - INTERVAL '365 days' THEN 1
    END) AS transactions_last_12_months,

    -- Which accounts are used with this vendor
    STRING_AGG(DISTINCT account_name, ', ' ORDER BY account_name) AS accounts_used

  FROM transaction_vendors
  GROUP BY vendor_name, category, subcategory, store
),

vendor_metrics AS (
  SELECT
    *,
    -- Calculate days between first and last transaction
    (last_transaction_date - first_transaction_date) AS days_active,

    -- Days since last transaction
    (CURRENT_DATE - last_transaction_date) AS days_since_last_transaction,

    -- Average monthly spend (total / months active)
    CASE
      WHEN months_with_transactions > 0 THEN total_lifetime_spend / months_with_transactions
      ELSE 0
    END AS average_monthly_spend,

    -- Average annual spend
    CASE
      WHEN years_active > 0 THEN total_lifetime_spend / years_active
      ELSE total_lifetime_spend
    END AS average_annual_spend,

    -- Transaction frequency (transactions per month)
    CASE
      WHEN months_with_transactions > 0 THEN total_transactions::numeric / months_with_transactions
      ELSE 0
    END AS avg_transactions_per_month,

    -- Is this vendor still active?
    (last_transaction_date >= CURRENT_DATE - INTERVAL '90 days') AS is_currently_active,

    -- Spending consistency (lower stddev / avg = more consistent)
    CASE
      WHEN average_transaction_amount > 0 AND transaction_amount_stddev IS NOT NULL THEN
        1 - LEAST(1, transaction_amount_stddev / average_transaction_amount)
      ELSE 0
    END AS spending_consistency_score

  FROM vendor_aggregates
),

vendor_trends AS (
  SELECT
    *,

    -- Rank vendors by total spend
    RANK() OVER (ORDER BY total_lifetime_spend DESC) AS lifetime_spend_rank,
    RANK() OVER (PARTITION BY category ORDER BY total_lifetime_spend DESC) AS spend_rank_in_category,

    -- Rank by recent activity
    RANK() OVER (ORDER BY spend_last_12_months DESC) AS annual_spend_rank,
    RANK() OVER (ORDER BY spend_last_90_days DESC) AS quarterly_spend_rank,

    -- Percentile of total spend (what % of vendors spend less than this one)
    PERCENT_RANK() OVER (ORDER BY total_lifetime_spend) AS spend_percentile,

    -- Share of total spending in category
    total_lifetime_spend / SUM(total_lifetime_spend) OVER (PARTITION BY category) AS category_spend_share,

    -- Share of total spending overall
    total_lifetime_spend / SUM(total_lifetime_spend) OVER () AS overall_spend_share

  FROM vendor_metrics
),

vendor_classification AS (
  SELECT
    *,

    -- Classify spending tier
    CASE
      WHEN spend_percentile >= 0.95 THEN 'Top 5% (Major Vendor)'
      WHEN spend_percentile >= 0.90 THEN 'Top 10%'
      WHEN spend_percentile >= 0.75 THEN 'Top 25%'
      WHEN spend_percentile >= 0.50 THEN 'Above Average'
      ELSE 'Below Average'
    END AS spending_tier,

    -- Classify frequency
    CASE
      WHEN avg_transactions_per_month >= 4 THEN 'Very Frequent (4+/month)'
      WHEN avg_transactions_per_month >= 1 THEN 'Frequent (1-4/month)'
      WHEN avg_transactions_per_month >= 0.25 THEN 'Regular (Quarterly)'
      WHEN avg_transactions_per_month >= 0.08 THEN 'Occasional (Annual)'
      ELSE 'Rare'
    END AS transaction_frequency_tier,

    -- Relationship status
    CASE
      WHEN days_since_last_transaction <= 30 THEN 'Active (Last 30 days)'
      WHEN days_since_last_transaction <= 90 THEN 'Recent (Last 90 days)'
      WHEN days_since_last_transaction <= 180 THEN 'Inactive (<6 months)'
      WHEN days_since_last_transaction <= 365 THEN 'Dormant (<1 year)'
      ELSE 'Historical (>1 year ago)'
    END AS vendor_relationship_status,

    -- High-value vendor flag (top 20% of spending + frequent)
    (spend_percentile >= 0.80 AND avg_transactions_per_month >= 0.25) AS is_high_value_vendor,

    -- Subscription-like pattern (frequent, consistent amounts)
    (avg_transactions_per_month >= 0.8
     AND spending_consistency_score > 0.85
     AND is_currently_active) AS appears_subscription_like

  FROM vendor_trends
),

final_report AS (
  SELECT
    vendor_name,
    category,
    subcategory,
    store,

    -- Classification
    spending_tier,
    transaction_frequency_tier,
    vendor_relationship_status,
    is_high_value_vendor,
    appears_subscription_like,

    -- Activity dates
    first_transaction_date,
    last_transaction_date,
    days_active,
    days_since_last_transaction,
    is_currently_active,

    -- Transaction counts
    total_transactions,
    months_with_transactions,
    years_active,
    ROUND(avg_transactions_per_month, 2) AS avg_transactions_per_month,
    transactions_last_90_days,
    transactions_last_12_months,

    -- Spending amounts
    ROUND(total_lifetime_spend, 2) AS total_lifetime_spend,
    ROUND(average_transaction_amount, 2) AS average_transaction_amount,
    ROUND(median_transaction::numeric, 2) AS median_transaction_amount,
    ROUND(minimum_transaction, 2) AS minimum_transaction,
    ROUND(maximum_transaction, 2) AS maximum_transaction,
    ROUND(transaction_amount_stddev, 2) AS transaction_amount_stddev,

    -- Averages over time
    ROUND(average_monthly_spend, 2) AS average_monthly_spend,
    ROUND(average_annual_spend, 2) AS average_annual_spend,

    -- Recent spending
    ROUND(spend_last_90_days, 2) AS spend_last_90_days,
    ROUND(spend_last_12_months, 2) AS spend_last_12_months,

    -- Rankings
    lifetime_spend_rank,
    annual_spend_rank,
    quarterly_spend_rank,
    spend_rank_in_category,

    -- Shares
    ROUND((category_spend_share * 100)::numeric, 2) AS category_spend_share_pct,
    ROUND((overall_spend_share * 100)::numeric, 2) AS overall_spend_share_pct,
    ROUND((spend_percentile * 100)::numeric, 1) AS spend_percentile,

    -- Metrics
    ROUND(spending_consistency_score * 100, 1) AS spending_consistency_score,

    -- Other details
    accounts_used,

    CURRENT_TIMESTAMP AS report_generated_at

  FROM vendor_classification
)

SELECT * FROM final_report
ORDER BY total_lifetime_spend DESC
