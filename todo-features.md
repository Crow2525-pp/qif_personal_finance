# Family Finance Dashboard Roadmap

## Strategic Direction

Local UI review on 2026-02-04 shows critical regressions: uncategorized spend reads 100% for Jan 2026, Family Essentials/Emergency Fund/Month-to-Date pace panels are empty, and Cash Flow Drivers shows no rows (see `screenshots/executive-dashboard-lower-2026-02-04.png` and `screenshots/executive-dashboard-cashflow-drivers-2026-02-04.png`). Immediate priority is fixing these data-quality and availability issues so the executive dashboard is trustworthy again, targeting uncategorized spend <15% and restoring essentials/pacing signals.

Once those fixes land, move to family-first quick-glance views (childcare, groceries, emergency fund) and weekly pacing. Phase two remains forward-looking: upcoming recurring bills, seasonal prep, and education savings goals, while keeping cognitive load low for parents.

---

## Concrete Tasks (Priority Order)

[
  {
    "id": 40,
    "category": "dashboard-fix",
    "title": "Align mobile Executive Overview with monthly-first layout",
    "description": "Mirror hero row order and new MTD pacing panel in 01-executive-overview-mobile.json so mobile users see monthly cadence first.",
    "scope": "grafana/provisioning/dashboards/01-executive-overview-mobile.json",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 63,
    "category": "dashboard-fix",
    "title": "Move and format \"How to read\" section",
    "description": "Place the How-to-read guidance at the top of the dashboard with clear typography/bullets; ensure it collapses after first view to reduce clutter.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json layout and text panel",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 65,
    "category": "dashboard-fix",
    "title": "Reconcile spend benchmarks (groceries ~1000/mo, ex-mortgage 4-5k)",
    "description": "Validate source models so grocery spend approximates $1k/month and total spend excluding mortgage reads ~$4–5k; adjust category mappings/filters if misclassified.",
    "scope": "reporting.rpt_outflows_insights_dashboard; macros/metric_expense; grafana/provisioning/dashboards/executive-dashboard.json relevant panels",
    "effort": "medium",
    "status": "pending"
  },
  {
    "id": 25,
    "category": "dashboard-fix",
    "title": "Align Cash Flow Trend forecast one month forward",
    "description": "SQL: set forecast series time = month_date + interval '1 month' for forecasted_next_month_net_flow; limit to last 12 months. Grafana timeseries: show Net Cash Flow as bars, 3-Month Avg line, Forecast Next Month as dashed line with light fill; legend at bottom.",
    "scope": "reporting.rpt_cash_flow_analysis; grafana/provisioning/dashboards/executive-dashboard.json (Cash Flow Trend panel)",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 1,
    "category": "data-quality",
    "title": "Add top 20 uncategorized merchants to category mappings",
    "description": "Review the Top Uncategorized Merchants panel on Executive dashboard and add category mappings for the 20 highest-spend merchants to reduce uncategorized spend from 38.7% toward 15%",
    "scope": "seeds/category_mappings + dbt run",
    "effort": "small",
    "status": "in-progress",
    "notes": "Use scripts/categorize_transactions.py interactive tool. 19 patterns (1004 transactions) categorized in previous session. 2026-02-05: discovered categorization join was over-restrictive (account_name) and using memo instead of description; loosened join and switched to description matching, reducing uncategorized to ~8.1k/12.7k but majority still uncategorized—needs new merchant patterns in banking_categories.csv."
  },
  {
    "id": 2,
    "category": "data-quality",
    "title": "Create childcare-specific subcategory",
    "description": "Add 'Childcare & Early Education' as a subcategory under Family & Kids with mappings for daycare centers, preschools, and babysitting services",
    "scope": "seeds/category_mappings + dbt model update",
    "effort": "small",
    "status": "pending",
    "notes": "Add subcategory mappings in banking_categories.csv with subcategory='Childcare & Early Education'"
  },
  {
    "id": 6,
    "category": "family-insights",
    "title": "Create Grocery spending breakdown panel",
    "description": "Break down grocery spending by store (Coles, Woolworths, Aldi, etc.) with average basket size and visit frequency to identify shopping pattern opportunities",
    "scope": "Grafana Category Spending dashboard or Grocery dashboard",
    "effort": "small"
  },
  {
    "id": 7,
    "category": "upcoming-expenses",
    "title": "Add 'Bills Due Next 14 Days' panel",
    "description": "Surface recurring bills due in the next 2 weeks with amounts and due dates. Critical for cash flow planning around pay cycles",
    "scope": "New dbt model for recurring transaction detection + Grafana panel",
    "effort": "medium"
  },
  {
    "id": 8,
    "category": "mobile",
    "title": "Add 'This Week Summary' to mobile Executive Overview",
    "description": "Add compact panel showing: week spending vs pace, emergency fund months, and single biggest expense this week",
    "scope": "Grafana mobile Executive Overview dashboard",
    "effort": "small"
  },
  {
    "id": 9,
    "category": "data-quality",
    "title": "Add kids activities merchants to category mappings",
    "description": "Map swimming lessons, sports clubs, music classes, playgroups, and similar merchants to 'Kids Activities' subcategory",
    "scope": "seeds/category_mappings",
    "effort": "small"
  },
  {
    "id": 10,
    "category": "simplification",
    "title": "Create 'Parent Quick Check' dashboard",
    "description": "New single-page dashboard with only 6 panels: This Week Pace, Emergency Fund Months, Family Essentials Total, Biggest Unusual Expense, Uncategorized Count, Bills Due Soon",
    "scope": "New Grafana dashboard",
    "effort": "medium"
  },
  {
    "id": 11,
    "category": "savings-goals",
    "title": "Add education savings goal tracker",
    "description": "Track progress toward education fund goals (e.g., $X per child by school age). Show current balance, monthly contribution needed, and progress percentage",
    "scope": "Grafana Savings Analysis dashboard + goal configuration",
    "effort": "medium"
  },
  {
    "id": 12,
    "category": "family-insights",
    "title": "Add 'Cost Per Child' estimation panel",
    "description": "Divide Family & Kids category spending by number of children to show approximate monthly cost per child for budgeting discussions",
    "scope": "Grafana panel with configurable child count variable",
    "effort": "small"
  },
  {
    "id": 13,
    "category": "alerts",
    "title": "Add spending spike alert to Executive dashboard",
    "description": "Highlight when any category exceeds 150% of its 3-month average with the category name and overage amount prominently displayed",
    "scope": "Grafana conditional formatting + SQL",
    "effort": "small"
  },
  {
    "id": 14,
    "category": "seasonal",
    "title": "Add 'Seasonal Expense Preparation' panel",
    "description": "Show upcoming seasonal costs based on historical patterns: school term fees (Feb, Apr, Jul, Oct), Christmas (Nov-Dec), winter utilities (Jun-Aug), sports registration seasons",
    "scope": "New dbt model + Grafana panel",
    "effort": "medium"
  },
  {
    "id": 15,
    "category": "cash-flow",
    "title": "Add pay cycle cash flow projection",
    "description": "Project cash position at next pay date based on known bills and average daily discretionary spend. Answer: 'Will we make it to payday?'",
    "scope": "SQL model + Grafana panel",
    "effort": "medium"
  },
  {
    "id": 16,
    "category": "mobile",
    "title": "Add quick categorization link to mobile dashboards",
    "description": "Add deep link from mobile uncategorized count to Transaction Analysis filtered to uncategorized items for quick review during downtime",
    "scope": "Grafana mobile dashboard link configuration",
    "effort": "small"
  },
  {
    "id": 17,
    "category": "family-insights",
    "title": "Add 'Fixed vs Flexible' expense breakdown",
    "description": "Classify expenses as Fixed (mortgage, insurance, childcare) vs Flexible (dining, entertainment, shopping) to show actual discretionary budget available",
    "scope": "Category classification + Grafana panel",
    "effort": "medium"
  },
  {
    "id": 18,
    "category": "simplification",
    "title": "Add 'Top 3 Actions This Week' panel",
    "description": "Rule-based recommendations panel: e.g., 'Categorize 5 transactions', 'Grocery spend up 20% - check receipts', 'Transfer $X to emergency fund to hit 3-month target'",
    "scope": "SQL logic + Grafana panel on Parent Quick Check",
    "effort": "medium"
  },
  {
    "id": 19,
    "category": "data-quality",
    "title": "Add medical expense subcategories",
    "description": "Break down Health & Medical into: GP Visits, Pharmacy, Specialist, Hospital, Health Insurance to track kids' medical costs separately",
    "scope": "seeds/category_mappings + merchant classification",
    "effort": "small"
  },
  {
    "id": 20,
    "category": "reporting",
    "title": "Add monthly family finance summary text panel",
    "description": "Auto-generated plain English summary: 'In December, your family spent $X on essentials and $Y on discretionary items. Emergency fund covers N months. Biggest increase: Groceries (+$Z).'",
    "scope": "SQL text generation + Grafana text panel",
    "effort": "medium"
  },
  {
    "id": 47,
    "category": "dashboard-fix",
    "title": "Restore data to Family Essentials, Emergency Fund, and MTD Pace panels",
    "description": "Family Essentials stat shows 'No data', Emergency Fund gauge reads 0 months, and Month-to-Date pace panel is empty. Ensure models return rows for selected month with COALESCE fallbacks and that panels refresh on variable change.",
    "scope": "reporting.rpt_family_essentials; reporting.rpt_emergency_fund_coverage; reporting.rpt_weekly_spending_pace; grafana/provisioning/dashboards/executive-dashboard.json",
    "effort": "small",
    "status": "pending",
    "notes": "Issues visible on Feb 2026 view."
  },
  {
    "id": 48,
    "category": "dashboard-fix",
    "title": "Correct uncategorized spend percent in Data Quality Callouts",
    "description": "Callouts show 100% / $14,100 uncategorized for Jan 2026, likely due to divide-by-zero or wrong window. Recalculate contribution within selected window with zero-safe denominators and numeric percent units.",
    "scope": "reporting.rpt_outflows_insights_dashboard; grafana/provisioning/dashboards/executive-dashboard.json (Data Quality Callouts)",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 49,
    "category": "dashboard-fix",
    "title": "Fix text encoding/emoji in summary and KPI tables",
    "description": "Panel text renders mojibake (e.g., 'ðŸ“Š', 'Î” Ratio'). Ensure dashboard JSON saved in UTF-8, remove or replace emojis, and verify Grafana text panels/tables don't double-encode strings.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json (Executive Summary, KPI tables)",
    "effort": "tiny",
    "status": "pending"
  },
  {
    "id": 50,
    "category": "dashboard-fix",
    "title": "Dedupe and mask Top Uncategorized Merchants table",
    "description": "Table shows duplicated $2.90K merchants with internal payer labels. Add DISTINCT/deduping, recalc contribution_pct for current window, and apply friendly merchant display names or masking where appropriate.",
    "scope": "reporting.viz_uncategorized_transactions_with_original_memo; grafana/provisioning/dashboards/executive-dashboard.json (Top Uncategorized Merchants)",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 67,
    "category": "dashboard-consolidation",
    "title": "Merge Cash Flow Analysis, Monthly Budget Summary, and Expense Performance dashboards",
    "description": "Cash Flow Analysis, Monthly Budget Summary, and Expense Performance all cover the latest-month income/expense mix, savings/expense ratios, and trend charts with overlapping panels. Combine them into a single 'Monthly Cash Flow & Budget' dashboard with one instructions block, one freshness widget, unified KPI row (net cash flow, savings rate, expense ratio), and shared trend/variance visuals to reduce panel duplication and maintenance.",
    "scope": "grafana/provisioning/dashboards/cash-flow-analysis-dashboard.json; grafana/provisioning/dashboards/monthly-budget-summary-dashboard.json; grafana/provisioning/dashboards/expense-performance-dashboard.json; related reporting models reused across the three dashboards",
    "effort": "medium",
    "status": "pending"
  },
  {
    "id": 68,
    "category": "dashboard-consolidation",
    "title": "Consolidate Year-over-Year and Four-Year comparison dashboards",
    "description": "Year-over-Year Financial Comparison and Four-Year Financial Comparison both present annual performance deltas, multi-year averages, and income/expense/net worth trends. Create a single 'Annual Performance & Trends' dashboard that supports 1–4 year views via a toggle, keeps the annual scorecard, and removes duplicate layouts and instructions blocks.",
    "scope": "grafana/provisioning/dashboards/year-over-year-comparison-dashboard.json; grafana/provisioning/dashboards/four-year-financial-comparison-dashboard.json",
    "effort": "medium",
    "status": "pending"
  },
  {
    "id": 69,
    "category": "dashboard-consolidation",
    "title": "Combine Account Performance and Household Net Worth dashboards",
    "description": "Account Performance and Household Net Worth both chart balances, net position, and month-over-month changes. Fold them into a single 'Net Worth & Account Health' dashboard: keep one freshness widget, merge balance trend and net worth progression, and surface account-level drill-downs without duplicating panels across two dashboards.",
    "scope": "grafana/provisioning/dashboards/account-performance-dashboard.json; grafana/provisioning/dashboards/household-net-worth-dashboard.json",
    "effort": "medium",
    "status": "pending"
  },
  {
    "id": 70,
    "category": "dashboard-fix",
    "title": "Restore missing rpt_executive_dashboard source",
    "description": "Multiple dashboards still query reporting.rpt_executive_dashboard, which is absent in Postgres, yielding relation-not-found/No data errors. Recreate the view (or repoint panels to rpt_monthly_budget_summary / rpt_cash_flow_analysis equivalents) so Executive, Account Performance, Expense Performance, and Executive Overview mobile panels populate.",
    "scope": "dbt model for reporting.rpt_executive_dashboard; grafana/provisioning/dashboards/executive-dashboard.json; grafana/provisioning/dashboards/01-executive-overview-mobile.json; grafana/provisioning/dashboards/account-performance-dashboard.json; grafana/provisioning/dashboards/expense-performance-dashboard.json",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 71,
    "category": "dashboard-fix",
    "title": "Fix Amazon dashboard base fact reference",
    "description": "Amazon Spending dashboard references reporting.reporting__fact_transactions, which does not exist in the warehouse, causing its panels to return No data. Point queries to reporting.fct_transactions (or create a compat view) and re-test panel outputs.",
    "scope": "grafana/provisioning/dashboards/amazon-spending-dashboard.json; upstream fact table mapping in dbt if needed",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 72,
    "category": "dashboard-fix",
    "title": "Rebuild uncategorized transactions view for merchant tables",
    "description": "Panels that show uncategorized transactions by merchant error out because reporting.viz_uncategorized_transactions_with_original_memo is missing. Re-materialize the view (or retarget to rpt_outflows_insights_dashboard) so Cash Flow Analysis, Executive, Outflows Insights, and Transaction Analysis dashboards display merchant rows.",
    "scope": "dbt model for reporting.viz_uncategorized_transactions_with_original_memo; grafana/provisioning/dashboards/{cash-flow-analysis-dashboard.json, executive-dashboard.json, outflows-insights-dashboard.json, transaction-analysis-dashboard.json}",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 73,
    "category": "dashboard-fix",
    "title": "Replace missing transformation.fct_transactions in Monthly Budget Summary",
    "description": "Monthly Budget Summary panels query transformation.fct_transactions, which is not present in the database, leading to empty visualizations. Update raw SQL to use reporting.fct_transactions (or create the transformation schema view) and confirm data renders.",
    "scope": "grafana/provisioning/dashboards/monthly-budget-summary-dashboard.json; dbt model for transformation.fct_transactions alias if preferred",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 74,
    "category": "dashboard-fix",
    "title": "Populate grocery viz tables (0 rows)",
    "description": "Grocery dashboards are blank because reporting.viz_grocery_monthly_summary, reporting.viz_grocery_order_context, and reporting.viz_grocery_spending_analysis currently contain zero rows. Refresh or fix the upstream dbt models so these views emit data for recent months.",
    "scope": "pipeline_personal_finance/dbt_finance models feeding grocery viz tables; grafana/provisioning/dashboards/grocery-spending-dashboard.json; grafana/provisioning/dashboards/03-spending-categories-mobile.json",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 75,
    "category": "data-quality",
    "title": "Backfill uncategorized examples view (0 rows)",
    "description": "reporting.viz_uncategorized_missing_example_top5 returns zero rows, leaving example panels empty on Executive Overview mobile and outflows dashboards. Recompute the view so it surfaces sample uncategorized transactions for the selected window.",
    "scope": "dbt model for reporting.viz_uncategorized_missing_example_top5; grafana/provisioning/dashboards/{01-executive-overview-mobile.json, outflows-insights-dashboard.json, outflows-reconciliation-dashboard.json}",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 76,
    "category": "dashboard-fix",
    "title": "Fill fixed vs discretionary split (0 rows)",
    "description": "Monthly Budget Summary includes panels fed by reporting.rpt_budget_cockpit_fixed_vs_discretionary, which currently has zero rows, producing No data. Repair the model to emit monthly fixed vs discretionary totals and verify the dashboard panels render.",
    "scope": "pipeline_personal_finance/dbt_finance/models/reporting/budget/rpt_budget_cockpit_fixed_vs_discretionary.sql; grafana/provisioning/dashboards/monthly-budget-summary-dashboard.json",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 77,
    "category": "dashboard-fix",
    "title": "Resolve Grafana Postgres query 400 errors across dashboards",
    "description": "Multiple dashboards log failed /api/ds/query calls (HTTP 400) and variable validation errors when loading panels, which surfaces as 'Error' in the UI. Audit the grafana-postgresql datasource, template variables, and SQL syntax/parameterization so queries execute cleanly without Bad Request responses.",
    "scope": "Grafana datasource settings; dashboard variables and SQL queries across all dashboards",
    "effort": "medium",
    "status": "pending",
    "notes": "Observed on Account Performance, Amazon Spending, Executive Overview, and several mobile dashboards during 2026-02-05 review."
  },
  {
    "id": 78,
    "category": "dashboard-fix",
    "title": "Restore data in dashboards showing 'No data' panels",
    "description": "Panels show 'No data' on multiple dashboards (Account Performance, Amazon Spending Analysis, Category Spending Analysis, Executive Financial Overview, Expense Performance Analysis, Grocery Spending Analysis, Household Net Worth Analysis, Mortgage Payoff, Outflows Insights, and mobile Executive Overview). Identify the missing/empty sources for each dashboard and ensure queries return rows for the current time range.",
    "scope": "Grafana dashboard JSONs and their upstream reporting models feeding the affected panels",
    "effort": "medium",
    "status": "pending",
    "notes": "Detected via live Grafana review on 2026-02-05."
  },
  {
    "id": 79,
    "category": "documentation",
    "title": "Publish monthly review dashboard priority list",
    "description": "Add and maintain the ranked monthly review order in `dashboard-priority.md`, including priority prefixes in dashboard names and rationale for the ordering.",
    "scope": "dashboard-priority.md",
    "effort": "tiny",
    "status": "done",
    "notes": "COMPLETED (2026-02-06): Renamed all 23 dashboard files with priority prefixes (01-23) according to dashboard-priority.md. Desktop dashboards 01-17, mobile dashboards 18-23. Commit: 86ad299"
  },
  {
    "id": 80,
    "category": "dashboard-feature",
    "title": "Add explicit budget target vs actual framework to Monthly Budget Summary",
    "description": "Dashboard 03 shows spending levels and ratios but does not clearly answer budget adherence because planned targets are missing. Add category-level monthly budget targets and variance KPIs (actual, target, variance $, variance %) with red/amber/green thresholds.",
    "scope": "reporting budget target model + grafana/provisioning/dashboards/03-monthly-budget-summary.json",
    "effort": "medium",
    "status": "pending"
  },
  {
    "id": 81,
    "category": "dashboard-feature",
    "title": "Add net worth movement attribution bridge",
    "description": "Dashboard 04 should explain what changed net worth month-over-month (savings contribution, debt paydown, valuation/other). Add a bridge/decomposition panel so users can act on drivers rather than just seeing totals.",
    "scope": "reporting model for net worth drivers + grafana/provisioning/dashboards/04-household-net-worth-analysis.json",
    "effort": "medium",
    "status": "pending"
  },
  {
    "id": 82,
    "category": "dashboard-feature",
    "title": "Add savings driver attribution (income effect vs spending effect)",
    "description": "Dashboard 05 reports savings outcomes but weakly explains causality. Add a panel decomposing savings-rate change into income increase, expense decrease, and one-off effects.",
    "scope": "reporting model for savings attribution + grafana/provisioning/dashboards/05-savings-analysis.json",
    "effort": "medium",
    "status": "pending"
  },
  {
    "id": 83,
    "category": "dashboard-feature",
    "title": "Add category drill-through from Category Spending to Transaction Analysis",
    "description": "Dashboard 06 highlights variance drivers but lacks direct drill-down to underlying transactions. Add click-through links with category/month parameters into Dashboard 09.",
    "scope": "grafana/provisioning/dashboards/06-category-spending-analysis.json; grafana/provisioning/dashboards/09-transaction-analysis.json links/variables",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 84,
    "category": "dashboard-feature",
    "title": "Add outlier transactions panel to Expense Performance",
    "description": "Dashboard 07 is expected to identify outliers but currently emphasizes ratios and top categories. Add a ranked table of statistically unusual transactions (z-score/IQR threshold) with merchant, amount, and category.",
    "scope": "outlier detection SQL model + grafana/provisioning/dashboards/07-expense-performance-analysis.json",
    "effort": "medium",
    "status": "pending"
  },
  {
    "id": 85,
    "category": "dashboard-feature",
    "title": "Add concentration risk metrics to Outflows Insights",
    "description": "Dashboard 08 should answer concentration risk (dependency on few categories/merchants). Add Top-3 share, Top-5 share, and a concentration index trend with thresholds.",
    "scope": "reporting concentration metrics + grafana/provisioning/dashboards/08-outflows-insights.json",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 86,
    "category": "dashboard-feature",
    "title": "Add interactive filters to Transaction Analysis dashboard",
    "description": "Dashboard 09 is a drilldown surface but lacks first-class filters for account, category, merchant, and review status. Add template variables and query bindings so anomaly triage can be done in-dashboard.",
    "scope": "grafana/provisioning/dashboards/09-transaction-analysis.json; reporting.viz_transaction_filter_options",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 87,
    "category": "dashboard-feature",
    "title": "Add reconciliation fix-priority queue with owner/SLA",
    "description": "Dashboard 10 shows failing tests but does not operationalize remediation. Add a queue view ranked by impact/severity with owner, due date, and linked dashboard/table to fix first.",
    "scope": "reporting.rpt_reconciliation_fix_order + grafana/provisioning/dashboards/10-financial-reconciliation.json",
    "effort": "medium",
    "status": "pending"
  },
  {
    "id": 88,
    "category": "dashboard-feature",
    "title": "Create cross-dashboard monthly review scorecard",
    "description": "Add one summary panel that rates readiness of dashboards 1-10 (data freshness, query health, no-data count, unresolved blockers) so review can start with confidence checks before financial interpretation.",
    "scope": "new reporting model + executive/reconciliation dashboard panel",
    "effort": "medium",
    "status": "pending"
  },
  {
    "id": 89,
    "category": "dashboard-feature",
    "title": "Add dashboard confidence badges per panel",
    "description": "Introduce lightweight confidence badges (Fresh, Stale, Partial, Error) based on freshness age and query errors so users can quickly judge whether each panel should influence decisions.",
    "scope": "shared Grafana panel conventions across dashboards 01-10",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 90,
    "category": "dashboard-feature",
    "title": "Add account-level drilldowns and normalized comparison metrics to Account Performance",
    "description": "Add transaction drilldowns from account trend panels and percent-change companion series so users can compare movements across accounts of different scale.",
    "scope": "grafana/provisioning/dashboards/11-account-performance.json; linked transaction drillthrough",
    "effort": "medium",
    "status": "pending"
  },
  {
    "id": 91,
    "category": "dashboard-feature",
    "title": "Add forecast confidence and backtesting to Financial Projections",
    "description": "Introduce uncertainty bands, model version/timestamp, and backtest error views (e.g., MAPE/residual trend) to improve trust in scenario outputs.",
    "scope": "reporting projection QA models + grafana/provisioning/dashboards/12-financial-projections.json",
    "effort": "medium",
    "status": "pending"
  },
  {
    "id": 92,
    "category": "dashboard-feature",
    "title": "Add benchmark and outlier context to Year-over-Year dashboard",
    "description": "Add target benchmark lines, outlier-year annotations, and annual-to-monthly reconciliation indicators to make YoY results actionable.",
    "scope": "grafana/provisioning/dashboards/13-year-over-year-comparison.json",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 93,
    "category": "dashboard-feature",
    "title": "Add decomposition and drilldowns to Four-Year comparison",
    "description": "Add assets-vs-liabilities decomposition and direct links into YoY/monthly dashboards for metric root-cause analysis.",
    "scope": "grafana/provisioning/dashboards/14-four-year-financial-comparison.json",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 94,
    "category": "dashboard-feature",
    "title": "Enhance Mortgage Payoff with uncertainty and recommendation outputs",
    "description": "Add payoff forecast extension with uncertainty band, cumulative interest-saved by scenario, and an action-oriented recommendation summary.",
    "scope": "reporting mortgage scenario models + grafana/provisioning/dashboards/15-mortgage-payoff.json",
    "effort": "medium",
    "status": "pending"
  },
  {
    "id": 95,
    "category": "dashboard-feature",
    "title": "Add anomaly detection and reconciliation checks to Grocery Spending dashboard",
    "description": "Add month-spike alerts and a grocery-to-total-expense reconciliation panel to improve decision confidence.",
    "scope": "grafana/provisioning/dashboards/16-grocery-spending-analysis.json",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 96,
    "category": "dashboard-feature",
    "title": "Add classification-confidence and anomaly alerting to Amazon Spending dashboard",
    "description": "Add confidence score for Amazon merchant parsing and alerts for unusual order frequency or basket inflation.",
    "scope": "grafana/provisioning/dashboards/17-amazon-spending-analysis.json",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 97,
    "category": "dashboard-feature",
    "title": "Add actionability layer to Executive Overview mobile dashboard",
    "description": "Add failed-check drillthrough links, compact next-actions list, and deep links to desktop dashboards for each KPI domain.",
    "scope": "grafana/provisioning/dashboards/18-executive-overview-mobile.json",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 98,
    "category": "dashboard-feature",
    "title": "Add comparative and drillthrough capabilities to Spending & Categories mobile dashboard",
    "description": "Add current-vs-previous comparator views, anomaly indicators, and row-level drillthrough to transaction details.",
    "scope": "grafana/provisioning/dashboards/19-spending-categories-mobile.json",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 99,
    "category": "dashboard-feature",
    "title": "Add budget-performance diagnostic layer to Cash Flow & Budget mobile dashboard",
    "description": "Add budget target overlays, variance decomposition by category, smoothing options, and recommendation text tied to current savings outcomes.",
    "scope": "grafana/provisioning/dashboards/20-cash-flow-budget-mobile.json",
    "effort": "medium",
    "status": "pending"
  },
  {
    "id": 100,
    "category": "dashboard-feature",
    "title": "Add assumptions/definitions strip to mobile analytical dashboards 21-23",
    "description": "Add compact per-dashboard assumptions block (YTD basis, savings-rate formula, projection horizon, sign conventions) so mobile users can interpret KPIs without opening desktop dashboards.",
    "scope": "grafana/provisioning/dashboards/21-savings-performance-mobile.json; grafana/provisioning/dashboards/22-assets-networth-mobile.json; grafana/provisioning/dashboards/23-projections-analysis-mobile.json",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 101,
    "category": "dashboard-feature",
    "title": "Add diagnostic drilldowns from mobile KPI anomalies",
    "description": "When KPIs show suspect values (e.g., 0% savings with large projected annual savings), provide one-tap drilldowns to source tables/panels that explain the calculation inputs.",
    "scope": "mobile dashboards 21-23 plus linked desktop dashboards",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 102,
    "category": "dashboard-feature",
    "title": "Add projection quality panel to 23-mobile",
    "description": "Add a compact quality panel showing scenario coverage horizon, last model run timestamp, and confidence/backtest indicator to improve trust in projection outputs.",
    "scope": "grafana/provisioning/dashboards/23-projections-analysis-mobile.json; projection QA model",
    "effort": "medium",
    "status": "pending"
  }
]

