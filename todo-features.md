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
    "status": "pending",
    "notes": "Added priority-ranked list on 2026-02-06."
  }
]
