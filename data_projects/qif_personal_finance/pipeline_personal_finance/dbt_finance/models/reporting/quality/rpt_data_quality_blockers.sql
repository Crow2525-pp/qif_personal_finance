{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['blocker_rank'], 'unique': false},
      {'columns': ['severity'], 'unique': false}
    ]
  )
}}

-- Identify and summarize the top data-quality blockers impacting dashboards
WITH latest_tests AS (
  SELECT
    MAX(period_date) AS latest_date
  FROM {{ ref('rpt_financials_reconciliation_tests') }}
),

failed_by_category AS (
  SELECT
    domain,
    COUNT(*) FILTER (WHERE NOT pass) AS failure_count,
    SUM(ABS(COALESCE(delta, 0))) FILTER (WHERE NOT pass)::numeric AS total_financial_impact
  FROM {{ ref('rpt_financials_reconciliation_tests') }}
  WHERE period_date = (SELECT latest_date FROM latest_tests)
  GROUP BY domain
),

-- Define blocker categories based on impact and prevalence
categorized_blockers AS (
  SELECT
    domain,
    failure_count,
    total_financial_impact,
    CASE
      WHEN domain = 'Outflows' THEN 'Uncategorized Transactions'
      WHEN domain = 'Budget' THEN 'Budget Formula Inconsistencies'
      WHEN domain = 'IncomeExpense' THEN 'Income/Expense Reconciliation'
      WHEN domain = 'CashFlow' THEN 'Cash Flow Component Alignment'
      WHEN domain = 'Executive' THEN 'Executive Dashboard Metrics'
      WHEN domain = 'NetWorth' THEN 'Net Worth Calculation'
      WHEN domain = 'Balances' THEN 'Account Balance Tracking'
      WHEN domain = 'Fact' THEN 'Fact Table Consistency'
      WHEN domain = 'Income' THEN 'Income Categorization'
      ELSE 'Other Data Quality Issues'
    END AS blocker_name,
    CASE
      WHEN domain = 'Outflows' THEN 'Prevents accurate spending analysis and category-level insights; impairs budget vs actual comparisons'
      WHEN domain = 'Budget' THEN 'Undermines monthly budget cockpit and savings rate calculations; impacts cash flow guidance'
      WHEN domain = 'IncomeExpense' THEN 'Divergence between visualizations and underlying budget; affects decision-making confidence'
      WHEN domain = 'CashFlow' THEN 'Compromises cash flow forecasting and liquidity analysis; affects operational planning'
      WHEN domain = 'Executive' THEN 'Executive dashboard KPIs unreliable; breaks trust in high-level metrics'
      WHEN domain = 'NetWorth' THEN 'Net worth tracking unreliable; property valuation or account balance issues'
      WHEN domain = 'Balances' THEN 'Daily balance tracking diverges from facts; breaks account reconciliation'
      WHEN domain = 'Fact' THEN 'Underlying transaction data inconsistent; cascading issues across all reports'
      WHEN domain = 'Income' THEN 'Income source tracking incomplete; affects cash flow and savings projections'
      ELSE 'Multiple downstream impacts across dashboards'
    END AS impact_description,
    CASE
      WHEN failure_count >= 5 OR total_financial_impact > 50000 THEN 'CRITICAL'
      WHEN failure_count >= 3 OR total_financial_impact > 20000 THEN 'HIGH'
      WHEN failure_count >= 1 OR total_financial_impact > 5000 THEN 'MEDIUM'
      ELSE 'LOW'
    END AS severity,
    ROW_NUMBER() OVER (
      ORDER BY
        CASE
          WHEN failure_count >= 5 OR total_financial_impact > 50000 THEN 1
          WHEN failure_count >= 3 OR total_financial_impact > 20000 THEN 2
          WHEN failure_count >= 1 OR total_financial_impact > 5000 THEN 3
          ELSE 4
        END,
        failure_count DESC,
        total_financial_impact DESC
    ) AS blocker_rank
  FROM failed_by_category
),

-- Link to affected dashboards and remediation steps
enriched_blockers AS (
  SELECT
    blocker_rank,
    domain,
    blocker_name,
    severity,
    failure_count,
    total_financial_impact,
    impact_description,
    CASE
      WHEN domain = 'Outflows' THEN 'outflows-reconciliation, category-spending-analysis'
      WHEN domain = 'Budget' THEN 'monthly-budget-summary, executive-financial-overview'
      WHEN domain = 'IncomeExpense' THEN 'executive-financial-overview, cash-flow-analysis'
      WHEN domain = 'CashFlow' THEN 'cash-flow-analysis, executive-financial-overview'
      WHEN domain = 'Executive' THEN 'executive-financial-overview'
      WHEN domain = 'NetWorth' THEN 'household-net-worth, account-performance'
      WHEN domain = 'Balances' THEN 'account-performance, cash-flow-analysis'
      WHEN domain = 'Fact' THEN 'all-dashboards'
      WHEN domain = 'Income' THEN 'cash-flow-analysis, executive-financial-overview'
      ELSE 'transaction-analysis'
    END AS affected_dashboards,
    CASE
      WHEN domain = 'Outflows' THEN 'Batch categorize uncategorized transactions; add merchant rules if needed'
      WHEN domain = 'Budget' THEN 'Review dbt model formulas; validate calculation logic against requirements'
      WHEN domain = 'IncomeExpense' THEN 'Check transaction filtering and grouping logic in viz models'
      WHEN domain = 'CashFlow' THEN 'Verify cash flow categorization and component assignments'
      WHEN domain = 'Executive' THEN 'Cross-check executive model joins and aggregations with source tables'
      WHEN domain = 'NetWorth' THEN 'Verify account balances and property valuations are current'
      WHEN domain = 'Balances' THEN 'Reconcile daily balance calculations with transaction facts'
      WHEN domain = 'Fact' THEN 'Audit source transaction data and fix at landing zone'
      WHEN domain = 'Income' THEN 'Review income categorization rules and transaction mappings'
      ELSE 'Review underlying model and data lineage'
    END AS remediation_steps
  FROM categorized_blockers
  WHERE failure_count > 0
)

SELECT
  blocker_rank,
  blocker_name,
  severity,
  domain,
  failure_count,
  total_financial_impact,
  impact_description,
  affected_dashboards,
  remediation_steps
FROM enriched_blockers
ORDER BY blocker_rank
