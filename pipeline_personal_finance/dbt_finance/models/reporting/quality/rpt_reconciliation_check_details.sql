{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['test_name'], 'unique': false},
      {'columns': ['affected_entity_type'], 'unique': false},
      {'columns': ['pass'], 'unique': false}
    ]
  )
}}

-- Detailed view of failed reconciliation checks with direct links to offending accounts/categories
WITH latest_tests AS (
  SELECT
    MAX(period_date) AS latest_date
  FROM {{ ref('rpt_financials_reconciliation_tests') }}
),

base_tests AS (
  SELECT
    period_date,
    domain,
    test_name,
    left_value,
    right_value,
    delta,
    notes,
    pass
  FROM {{ ref('rpt_financials_reconciliation_tests') }}
  WHERE period_date = (SELECT latest_date FROM latest_tests)
),

-- Extract affected accounts for tests involving account/balance checks
account_details AS (
  SELECT
    bt.period_date,
    bt.domain,
    bt.test_name,
    'Account' AS affected_entity_type,
    NULL::text AS account_name,
    NULL::text AS entity_category,
    bt.left_value,
    bt.right_value,
    bt.delta,
    bt.notes,
    bt.pass,
    CASE
      WHEN bt.test_name LIKE '%daily_eom%' THEN 'account-performance'
      WHEN bt.test_name LIKE '%ppor%' THEN 'household-net-worth'
      ELSE 'account-performance'
    END AS recommended_dashboard
  FROM base_tests bt
  WHERE bt.domain IN ('Balances', 'NetWorth')
    AND NOT bt.pass
),

-- Extract affected categories for tests involving category checks
category_details AS (
  SELECT
    bt.period_date,
    bt.domain,
    bt.test_name,
    'Category' AS affected_entity_type,
    NULL::text AS account_name,
    CASE
      WHEN bt.test_name LIKE '%food%' THEN 'Food & Dining'
      WHEN bt.test_name LIKE '%household%' THEN 'Household & Utilities'
      WHEN bt.test_name LIKE '%mortgage%' THEN 'Housing & Mortgage'
      WHEN bt.test_name LIKE '%family%' THEN 'Family & Kids'
      WHEN bt.test_name LIKE '%uncategorized%' THEN 'Uncategorized'
      ELSE 'Multiple Categories'
    END AS entity_category,
    bt.left_value,
    bt.right_value,
    bt.delta,
    bt.notes,
    bt.pass,
    CASE
      WHEN bt.test_name LIKE '%uncategorized%' THEN 'outflows-reconciliation'
      WHEN bt.test_name LIKE '%cat_%' THEN 'category-spending-analysis'
      ELSE 'outflows-reconciliation'
    END AS recommended_dashboard
  FROM base_tests bt
  WHERE bt.domain IN ('Outflows', 'Budget', 'Income')
    AND (bt.test_name LIKE '%cat_%' OR bt.test_name LIKE '%uncategorized%')
    AND NOT bt.pass
),

-- Extract checks that span multiple domains
cross_domain_details AS (
  SELECT
    bt.period_date,
    bt.domain,
    bt.test_name,
    'Cross-Domain' AS affected_entity_type,
    NULL::text AS account_name,
    bt.domain AS entity_category,
    bt.left_value,
    bt.right_value,
    bt.delta,
    bt.notes,
    bt.pass,
    CASE
      WHEN bt.domain = 'Budget' AND bt.test_name LIKE '%mbs_%' THEN 'monthly-budget-summary'
      WHEN bt.domain = 'IncomeExpense' THEN 'executive-financial-overview'
      WHEN bt.domain = 'CashFlow' THEN 'cash-flow-analysis'
      WHEN bt.domain = 'Executive' THEN 'executive-financial-overview'
      ELSE 'executive-financial-overview'
    END AS recommended_dashboard
  FROM base_tests bt
  WHERE bt.domain IN ('Budget', 'IncomeExpense', 'CashFlow', 'Executive', 'Fact')
    AND NOT bt.pass
)

SELECT
  period_date,
  domain,
  test_name,
  affected_entity_type,
  account_name,
  entity_category,
  left_value,
  right_value,
  delta,
  notes,
  pass,
  recommended_dashboard,
  CASE
    WHEN NOT pass THEN 'Check failed - investigate details'
    ELSE 'Check passed'
  END AS status
FROM account_details

UNION ALL

SELECT
  period_date,
  domain,
  test_name,
  affected_entity_type,
  account_name,
  entity_category,
  left_value,
  right_value,
  delta,
  notes,
  pass,
  recommended_dashboard,
  CASE
    WHEN NOT pass THEN 'Check failed - investigate details'
    ELSE 'Check passed'
  END AS status
FROM category_details

UNION ALL

SELECT
  period_date,
  domain,
  test_name,
  affected_entity_type,
  account_name,
  entity_category,
  left_value,
  right_value,
  delta,
  notes,
  pass,
  recommended_dashboard,
  CASE
    WHEN NOT pass THEN 'Check failed - investigate details'
    ELSE 'Check passed'
  END AS status
FROM cross_domain_details

ORDER BY pass, domain, test_name
