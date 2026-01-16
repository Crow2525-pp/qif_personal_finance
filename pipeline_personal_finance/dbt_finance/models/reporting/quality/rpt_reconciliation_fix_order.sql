{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['priority_rank'], 'unique': false},
      {'columns': ['status'], 'unique': false}
    ]
  )
}}

-- Consolidate failed tests and rank by financial impact
WITH latest_tests AS (
  SELECT
    MAX(period_date) AS latest_date
  FROM {{ ref('rpt_financials_reconciliation_tests') }}
),

failed_checks AS (
  SELECT
    t.period_date,
    t.domain,
    t.test_name,
    t.left_value,
    t.right_value,
    t.delta,
    t.notes,
    CASE
      WHEN NOT t.pass THEN 'FAILED'
      ELSE 'PASSED'
    END AS status
  FROM {{ ref('rpt_financials_reconciliation_tests') }} t
  WHERE t.period_date = (SELECT latest_date FROM latest_tests)
    AND NOT t.pass
),

-- Categorize issues by impact type and magnitude
impact_scored AS (
  SELECT
    domain,
    test_name,
    left_value,
    right_value,
    delta,
    notes,
    status,
    ABS(COALESCE(delta, 0))::numeric AS abs_delta,
    CASE
      WHEN domain = 'Outflows' AND test_name LIKE '%uncategorized%' THEN 100
      WHEN domain = 'Budget' AND test_name LIKE '%mbs_%' THEN 90
      WHEN domain = 'IncomeExpense' THEN 85
      WHEN domain = 'CashFlow' THEN 80
      WHEN domain = 'Executive' THEN 75
      WHEN domain = 'NetWorth' THEN 60
      WHEN domain = 'Balances' THEN 50
      WHEN domain = 'Fact' THEN 40
      WHEN domain = 'Income' THEN 30
      ELSE 20
    END AS impact_weight,
    ROW_NUMBER() OVER (
      ORDER BY
        ABS(COALESCE(delta, 0)) DESC NULLS LAST,
        CASE
          WHEN domain = 'Outflows' AND test_name LIKE '%uncategorized%' THEN 100
          WHEN domain = 'Budget' AND test_name LIKE '%mbs_%' THEN 90
          WHEN domain = 'IncomeExpense' THEN 85
          WHEN domain = 'CashFlow' THEN 80
          WHEN domain = 'Executive' THEN 75
          WHEN domain = 'NetWorth' THEN 60
          WHEN domain = 'Balances' THEN 50
          WHEN domain = 'Fact' THEN 40
          WHEN domain = 'Income' THEN 30
          ELSE 20
        END DESC
    ) AS priority_rank
  FROM failed_checks
),

-- Enrich with dashboard and link context
dashboard_links AS (
  SELECT
    priority_rank,
    domain,
    test_name,
    left_value,
    right_value,
    abs_delta,
    delta,
    impact_weight,
    status,
    notes,
    CASE
      WHEN domain = 'Outflows' THEN 'outflows-reconciliation'
      WHEN domain = 'Budget' THEN 'monthly-budget-summary'
      WHEN domain = 'IncomeExpense' THEN 'executive-financial-overview'
      WHEN domain = 'CashFlow' THEN 'cash-flow-analysis'
      WHEN domain = 'Executive' THEN 'executive-financial-overview'
      WHEN domain = 'NetWorth' THEN 'household-net-worth'
      WHEN domain = 'Balances' THEN 'account-performance'
      ELSE 'transaction-analysis'
    END AS affected_dashboard,
    CASE
      WHEN domain = 'Outflows' AND test_name LIKE '%uncategorized%' THEN 'Review and categorize uncategorized transactions to improve data quality and dashboard accuracy'
      WHEN domain = 'Budget' AND test_name LIKE '%derivation%' THEN 'Verify budget formula derivations match expected calculations'
      WHEN domain = 'Budget' AND test_name LIKE '%mbs_income%' THEN 'Reconcile budget income totals with fact table; check for missing income transactions'
      WHEN domain = 'Budget' AND test_name LIKE '%mbs_expense%' THEN 'Reconcile budget expenses with fact table; verify expense categorization and filtering'
      WHEN domain = 'Budget' AND test_name LIKE '%mbs_net%' THEN 'Verify net cash flow calculation; check for unaccounted transfers or fees'
      WHEN domain = 'IncomeExpense' AND test_name LIKE '%viz_vs_budget_income%' THEN 'Check viz income view for missing transactions or incorrect filtering'
      WHEN domain = 'IncomeExpense' AND test_name LIKE '%viz_vs_budget_expense%' THEN 'Check viz expense view for missing transactions or incorrect categorization'
      WHEN domain = 'CashFlow' AND test_name LIKE '%net_equals%' THEN 'Verify operating, financing, and investing flows sum to net; check categorization'
      WHEN domain = 'CashFlow' AND test_name LIKE '%derivation%' THEN 'Check cash flow ratio derivations for formula errors'
      WHEN domain = 'Executive' THEN 'Executive dashboard metrics diverging from source tables; investigate data lineage'
      WHEN domain = 'NetWorth' AND test_name LIKE '%equation%' THEN 'Verify net worth calculation (assets - liabilities); check for missing accounts'
      WHEN domain = 'NetWorth' AND test_name LIKE '%ppor%' THEN 'Property valuation data missing or invalid; check property asset configuration'
      WHEN domain = 'Balances' THEN 'Daily balance tracking diverging from transaction facts; check reconciliation'
      ELSE 'Investigate data quality issue; review underlying transactions and categorization'
    END AS recommended_action
  FROM impact_scored
)

SELECT
  priority_rank,
  domain,
  test_name,
  status,
  affected_dashboard,
  recommended_action,
  abs_delta AS financial_impact,
  delta AS variance,
  left_value,
  right_value,
  notes,
  impact_weight
FROM dashboard_links
ORDER BY priority_rank
