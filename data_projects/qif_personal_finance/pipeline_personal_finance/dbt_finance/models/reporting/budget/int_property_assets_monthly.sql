{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['budget_year_month'], 'unique': false},
      {'columns': ['account_name'], 'unique': false}
    ]
  )
}}

WITH props AS (
  SELECT 
    asset_id,
    asset_name,
    display_name,
    asset_type,
    purchase_date::date AS purchase_date,
    purchase_price::numeric AS purchase_price,
    COALESCE(appreciation_rate_low::numeric, 0.0)  AS rate_low,
    COALESCE(appreciation_rate_high::numeric, 0.0) AS rate_high,
    CASE 
      WHEN appreciation_rate_low IS NOT NULL AND appreciation_rate_high IS NOT NULL
      THEN ((appreciation_rate_low::numeric + appreciation_rate_high::numeric) / 2.0)
      WHEN appreciation_rate_low IS NOT NULL THEN appreciation_rate_low::numeric
      WHEN appreciation_rate_high IS NOT NULL THEN appreciation_rate_high::numeric
      ELSE 0.0
    END AS rate_mid
  FROM {{ ref('property_assets') }}
),

series AS (
  SELECT 
    p.asset_id,
    p.asset_name,
    p.display_name,
    p.asset_type,
    p.purchase_date,
    p.purchase_price,
    p.rate_low,
    p.rate_high,
    p.rate_mid,
    -- monthly series from purchase month to current month
    {% if target.type == 'duckdb' %}
    gs.month_start AS month_start
    {% else %}
    gs::date AS month_start
    {% endif %}
  FROM props p
  {% if target.type == 'duckdb' %}
  CROSS JOIN generate_series(
    date_trunc('month', p.purchase_date),
    date_trunc('month', current_date) - interval '1 month',
    interval '1 month'
  ) AS gs(month_start)
  {% else %}
  CROSS JOIN LATERAL generate_series(
    date_trunc('month', p.purchase_date),
    date_trunc('month', current_date) - interval '1 month',
    interval '1 month'
  ) AS gs
  {% endif %}
),

valuations AS (
  SELECT 
    s.asset_id,
    s.asset_name,
    s.display_name,
    s.asset_type,
    s.purchase_date,
    s.purchase_price,
    s.rate_low,
    s.rate_high,
    s.rate_mid,
    s.month_start,
    (date_part('year', age(s.month_start, s.purchase_date)) * 12 + date_part('month', age(s.month_start, s.purchase_date)))::int AS months_since_purchase,
    -- convert annual to monthly compounding
    CASE WHEN s.rate_low > 0 THEN POWER(1 + s.rate_low, 1.0/12.0) - 1 ELSE 0 END  AS m_low,
    CASE WHEN s.rate_high > 0 THEN POWER(1 + s.rate_high, 1.0/12.0) - 1 ELSE 0 END AS m_high,
    CASE WHEN s.rate_mid > 0 THEN POWER(1 + s.rate_mid, 1.0/12.0) - 1 ELSE 0 END  AS m_mid
  FROM series s
),

valuations_compounded AS (
  SELECT 
    v.*,
    -- compounded values using monthly rate
    ROUND(v.purchase_price * POWER(1 + v.m_low, GREATEST(0, v.months_since_purchase)), 2)  AS value_low,
    ROUND(v.purchase_price * POWER(1 + v.m_high, GREATEST(0, v.months_since_purchase)), 2) AS value_high,
    ROUND(v.purchase_price * POWER(1 + v.m_mid, GREATEST(0, v.months_since_purchase)), 2)  AS value_mid
  FROM valuations v
),

valuations_with_overrides AS (
  SELECT 
    vc.*,
    -- pull the most recent override on or before this month, if present
    (
      SELECT (o.market_value::text)::numeric
      FROM landing.property_valuation_overrides o
      WHERE o.asset_id::text = vc.asset_id::text
        AND date_trunc('month', (o.valuation_date::text)::date) <= vc.month_start
      ORDER BY (o.valuation_date::text)::date DESC
      LIMIT 1
    ) AS override_value
  FROM valuations_compounded vc
)

SELECT 
  EXTRACT(YEAR FROM month_start)::int                 AS transaction_year,
  EXTRACT(MONTH FROM month_start)::int                AS transaction_month,
  TO_CHAR(month_start, 'YYYY-MM')                     AS budget_year_month,
  -- map to monthly_account_balances columns for union
  asset_name                                          AS account_name,
  'Property'                                          AS bank_name,
  'Property'                                          AS account_type,
  'Asset'                                             AS account_category,
  FALSE                                               AS is_liability,
  FALSE                                               AS is_liquid_asset,
  FALSE                                               AS is_mortgage,
  -- prefer override when available, otherwise midpoint valuation
  COALESCE(override_value, value_mid)                 AS end_of_month_balance,
  month_start                                         AS month_start_date,
  (month_start + INTERVAL '1 month' - INTERVAL '1 day')::date AS month_end_date,
  -- extras
  value_low,
  value_high
FROM valuations_with_overrides
ORDER BY transaction_year, transaction_month
