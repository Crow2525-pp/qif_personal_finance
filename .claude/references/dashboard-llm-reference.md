# Dashboard LLM Reference

Last updated: 2026-02-21

## Repository Goal
Make family-finance dashboards easy for parents to understand and act on without technical context.

## Source Of Truth
- Dashboard JSON: `grafana/provisioning/dashboards/*.json`
- Dashboard linter/checker: `scripts/check_grafana_dashboards.py`
- Dashboard docs: `grafana/provisioning/dashboards/README.md`
- dbt reporting models: `pipeline_personal_finance/dbt_finance/models/reporting/**/*.sql`
- dbt tests: `pipeline_personal_finance/dbt_finance/tests/*.sql`

## Findings From Live Review (Playwright + Grafana API)
- Runtime review completed on 2026-02-21 against `http://localhost:3001`.
- Dashboards with visible `No data` panels:
  - `executive_dashboard`: `Data Freshness`, `Monthly Financial Snapshot`
  - `category-spending-v2`: multiple variance and trend panels
  - `account_performance_dashboard`: trend/balance/mortgage panels
  - `household_net_worth`: `Net Worth Change Drivers (Top Account Movements)`
  - `expense_performance`: `Current Expense-to-Income Ratio`, `Expense Performance Metrics Summary`
  - `exec-mobile-overview`: `Health Scores`, `Key Metrics`
- Query/API errors captured from `/api/ds/query`:
  - missing relation: `reporting.rpt_executive_dashboard`
  - missing relation: `reporting.rpt_recommendation_outcomes`
  - missing relation: `reporting.reporting__fact_transactions`
  - missing columns: `bendigo_offset`, `bendigo_offset_MoM`, `inflow_excl_transfers`
  - type issue: `function make_date(bigint, bigint, integer) does not exist`
- Static lint parse errors:
  - `grafana/provisioning/dashboards/outflows-insights-dashboard.json`
  - `grafana/provisioning/dashboards/transaction-analysis-dashboard.json`
- Content/UX findings:
  - non-ASCII/emoji dashboard titles exist in mobile suite
  - markdown-heavy instruction panels (headers, bold, file-path references)
  - executive dashboard contains mutable `child_count` variable though household size is fixed
  - mixed time controls (`time_window`, `dashboard_period`, native picker hidden on executive)
  - chart semantics and tooltip consistency are uneven across dashboards

## Non-Negotiable Standards
- Prefer native Grafana time picker as the primary date control.
- Avoid visible `No data` for expected-use panels; return fallback explanatory rows instead.
- Remove emoji/non-ASCII and markdown artifacts from dashboard titles and user-facing text.
- Keep dashboard ordering explicit and stable (`01`, `02`, ...), desktop-first.
- Ensure links only target existing dashboards.
- Tooltips must provide meaningful context and values.

## Required Validation For Any Dashboard Task
1. `python scripts/check_grafana_dashboards.py --lint-only`
2. Targeted live checks:
   - `python scripts/check_grafana_dashboards.py --dashboard <uid-or-title> --days 365`
3. Playwright walkthrough of impacted dashboards:
   - Confirm no visible `No data` in affected panels.
   - Confirm navigation links resolve.
   - Capture screenshot evidence in `screenshots/`.
4. If dbt models are touched:
   - run dbt build/test for changed models and dependent tests.

## Playwright Review URLs
- `/d/executive_dashboard/e718165`
- `/d/cash_flow_analysis/cash-flow-analysis-most-recent-complete-month`
- `/d/category-spending-v2/category-spending-analysis`
- `/d/account_performance_dashboard/account-performance`
- `/d/monthly_budget_summary/monthly-budget-summary`
- `/d/outflows_reconciliation/financial-reconciliation-dashboard`
- `/d/savings_analysis/savings-analysis`
- `/d/household_net_worth/2dd8675`
- `/d/expense_performance/expense-performance-analysis`
- `/d/financial_projections/financial-projections-dashboard`
- `/d/exec-mobile-overview/f09f93b1-executive-overview`
- `/d/cashflow-budget-mobile/f09f92b0-cash-flow-and-budget`
- `/d/spending-categories-mobile/f09f92b3-spending-and-categories`
- `/d/assets-networth-mobile/f09f928e-assets-and-net-worth`
- `/d/savings-performance-mobile/f09f938a-savings-and-performance`
- `/d/projections-analysis-mobile/f09f94ae-projections-and-analysis`
