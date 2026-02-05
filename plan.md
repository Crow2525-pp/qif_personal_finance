# Family Finance Dashboard Roadmap

## Strategic Direction

Local UI review on 2026-02-04 shows critical regressions: uncategorized spend reads 100% for Jan 2026, Family Essentials/Emergency Fund/Month-to-Date pace panels are empty, and Cash Flow Drivers shows no rows (see `screenshots/executive-dashboard-lower-2026-02-04.png` and `screenshots/executive-dashboard-cashflow-drivers-2026-02-04.png`). Immediate priority is fixing these data-quality and availability issues so the executive dashboard is trustworthy again, targeting uncategorized spend <15% and restoring essentials/pacing signals.

Once those fixes land, move to family-first quick-glance views (childcare, groceries, emergency fund) and weekly pacing. Phase two remains forward-looking: upcoming recurring bills, seasonal prep, and education savings goals, while keeping cognitive load low for parents.

---

## Concrete Tasks (Priority Order)

[
  {
    "id": 41,
    "category": "dashboard-fix",
    "title": "Make time_window variable drive all Executive panels",
    "description": "In grafana/provisioning/dashboards/executive-dashboard.json, update every SQL query to honor $time_window via a shared window_range CTE (latest_month, ytd, trailing_12m). Replace single-month filters (= selected_period) with BETWEEN window_range.start_date and window_range.end_date and adjust aggregates (sums/avgs) accordingly for: Data Freshness, Key Executive KPIs table, Savings & Expense Performance, Cash Flow Trend timeseries, and any other month-scoped stat panels. Also set templating.list entries for time_window and dashboard_period to disallow custom values (allowCustom=false, queryOption.multi=false) to prevent invalid SQL.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; reporting.rpt_monthly_budget_summary; reporting.rpt_cash_flow_analysis",
    "effort": "medium",
    "status": "done",
    "notes": "16 panels updated via window_range CTE. Key Executive KPIs uses previous_window_range for period comparison. Family Essentials SUM is wired but rpt_family_essentials model still materialises latest month only — needs model update to expose all months (see task 45 scope)."
  },
  {
    "id": 42,
    "category": "dashboard-fix",
    "title": "Sync dashboard time picker with selected period",
    "description": "Ensure the Grafana dashboard time range follows the chosen month in $dashboard_period: set timepicker.hidden=true (dashboard-level) and programmatically set panel queries to use the selected period window instead of the URL time range now-1M/M..now/M. Prevents mismatches where panels show the selected month but the global range stays on the previous one.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json (timepicker block, defaults); reporting queries already windowed after task 41",
    "effort": "small",
    "status": "done",
    "notes": "Timepicker hidden; all panels already windowed via window_range CTE from task 41."
  },
  {
    "id": 43,
    "category": "dashboard-fix",
    "title": "Zero-safe deltas and ratios in Executive KPI tables",
    "description": "Guard division by zero and missing previous periods in Net Cash Flow and Forecast rows. SQL template: delta_ratio = CASE WHEN COALESCE(prev,0)=0 AND COALESCE(curr,0)=0 THEN 0 WHEN COALESCE(prev,0)=0 THEN NULL ELSE (curr-prev)/NULLIF(ABS(prev),0) END; delta_value = curr - COALESCE(prev,0). Apply the same logic to MoM Rate Changes. In JSON: set field.displayMode to 'color-text', nullValueMode='connected', and add 'text: n/a' override when value is null; keep percent unit.",
    "scope": "reporting.rpt_monthly_budget_summary; grafana/provisioning/dashboards/executive-dashboard.json (Key Executive KPIs, Month-over-Month Rate Changes tables)",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 44,
    "category": "dashboard-fix",
    "title": "Normalize percent units across rate panels",
    "description": "Standardize all percent outputs to 0–100 numeric scale. SQL: multiply ratios by 100 and alias without '%' chars. Panels to update: Savings & Expense Performance bars, MoM Rate Changes, Expense Ratio stats, uncategorized_pct in Data Quality Callouts. JSON: set fieldConfig.defaults.unit='percent', thresholds numeric (e.g., 5/10/20/30 or red>15 yellow>10 for data-quality), remove any suffix text '%'.",
    "scope": "reporting.rpt_monthly_budget_summary; reporting.rpt_outflows_insights_dashboard; grafana/provisioning/dashboards/executive-dashboard.json (Savings & Expense Performance, MoM Rate Changes, Data Quality Callouts, related stats)",
    "effort": "small",
    "status": "done",
    "notes": "Panel 101 MoM Rate Changes: SQL ×100 for current/previous/delta, JSON unit changed to percent. Consistent with Savings & Expense Performance bars."
  },
  {
    "id": 45,
    "category": "dashboard-fix",
    "title": "Apply selected period to data-quality and merchant panels",
    "description": "Filter Data Quality Callouts, Top Uncategorized Merchants, and AI Financial Insights to $time_window/$dashboard_period. SQL: add window_range CTE (start_date/end_date) and apply WHERE activity_date BETWEEN start_date AND end_date (or month_date for monthly models). For merchants: recompute contribution_pct within the filtered set and ORDER BY contribution_pct DESC LIMIT 10. JSON: pass both variables in links (?var-dashboard_period=$dashboard_period&var-time_window=$time_window) and set panels to refresh on variable change.",
    "scope": "reporting.rpt_outflows_insights_dashboard; reporting.viz_uncategorized_transactions_with_original_memo; grafana/provisioning/dashboards/executive-dashboard.json (Data Quality Callouts, Top Uncategorized Merchants, AI Financial Insights)",
    "effort": "medium",
    "status": "done",
    "notes": "Removed hardcoded last-month filter from viz_uncategorized view. Panel 901 transfer_pairs and uncategorized aggregated across window_range. Panel 902 recomputes contribution_pct within the filtered window. Links updated to pass both variables."
  },
  {
    "id": 31,
    "category": "dashboard-fix",
    "title": "Fix Monthly Income pull in Executive Snapshot",
    "description": "Use inflow_excl_transfers from reporting.rpt_cash_flow_analysis for selected month (COALESCE to 0) so Monthly Income is not $0; ensure datasource UID matches Postgres and join only on latest/selected month key.",
    "scope": "reporting.rpt_cash_flow_analysis; grafana/provisioning/dashboards/executive-dashboard.json (Monthly Financial Snapshot stat)",
    "effort": "small",
    "status": "done",
    "notes": "Monthly Income/Expenses populate correctly for Jan 2026 (see screenshots/executive-dashboard-full-2026-02-04.png)."
  },
  {
    "id": 32,
    "category": "dashboard-fix",
    "title": "Return real percentages in Savings & Expense Performance",
    "description": "Multiply ratios by 100 with divide-by-zero guards: savings_rate_pct, savings_rate_3m_pct, savings_rate_ytd_pct, expense_ratio_pct; set Grafana unit=percent and thresholds 5/10/20/30 so values no longer show 0%.",
    "scope": "reporting.rpt_monthly_budget_summary; grafana/provisioning/dashboards/executive-dashboard.json (Savings & Expense Performance bar gauge)",
    "effort": "small",
    "status": "done",
    "notes": "Savings Rate and Expense Ratio now show scaled % values (-10.2%, 4.2%, 110%) in UI (screenshots/executive-dashboard-full-2026-02-04.png)."
  },
  {
    "id": 33,
    "category": "dashboard-fix",
    "title": "Make Cash Flow Drivers panel always return rows",
    "description": "In MoM drivers query, select current and previous month even if prior is missing by defaulting to 0 rows; compute income_delta, expense_delta, transfers_delta, net_delta; ensure datasource UID is valid to stop 'No data'.",
    "scope": "reporting.rpt_monthly_budget_summary (plus transfers source); grafana/provisioning/dashboards/executive-dashboard.json (Cash Flow Drivers panel)",
    "effort": "small",
    "status": "pending",
    "notes": "Panel empty for Jan 2026 despite data (see screenshots/executive-dashboard-cashflow-drivers-2026-02-04.png)."
  },
  {
    "id": 34,
    "category": "dashboard-fix",
    "title": "Align liquid assets and net worth signs",
    "description": "Treat assets/liabilities as positive balances in both net worth and monthly snapshot queries; set net_worth = assets - liabilities; remove negative liquid_assets so snapshots and asset cards agree.",
    "scope": "reporting.rpt_household_net_worth; reporting.rpt_cash_flow_analysis snapshot fields; grafana/provisioning/dashboards/executive-dashboard.json (Asset & Liability Snapshot, Monthly Financial Snapshot)",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 35,
    "category": "dashboard-fix",
    "title": "Restore Cash Flow Trend as timeseries",
    "description": "Ensure query outputs time (month_date) and numeric series; set panel type timeseries with Net Cash Flow (bars), 3M Avg (line), Forecast (dashed line, shifted +1 month).",
    "scope": "reporting.rpt_cash_flow_analysis + grafana/provisioning/dashboards/executive-dashboard.json (Cash Flow Trend panel)",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 36,
    "category": "dashboard-fix",
    "title": "Replace WTD pace with Month-to-Date pace",
    "description": "Create MTD pace query: mtd_spend, monthly_budget, expected_spend_to_date, pace_ratio%, days_left_in_month; show pace_ratio with thresholds (<90 green, 90-110 yellow, >110 red) and secondary stats for budget/remaining.",
    "scope": "reporting.rpt_monthly_budget_summary or new rpt_monthly_pacing; grafana/provisioning/dashboards/executive-dashboard.json (replace WTD panel)",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 37,
    "category": "dashboard-fix",
    "title": "Reorder hero row for monthly cadence",
    "description": "Top layout order: Data Freshness → Monthly Financial Snapshot → Family Essentials → Emergency Fund → Cash Flow Drivers; move Data Quality Callouts directly under hero; fold detailed KPI tables into a collapsible section.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json layout",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 38,
    "category": "dashboard-fix",
    "title": "Enhance Data Quality Callouts for uncategorized risk",
    "description": "Return uncategorized_pct numeric plus uncategorized_amount; set percent thresholds red>15%, yellow>10%; add link to Transaction Analysis filtered to uncategorized items.",
    "scope": "reporting.rpt_outflows_insights_dashboard; grafana/provisioning/dashboards/executive-dashboard.json (Data Quality Callouts)",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 39,
    "category": "dashboard-fix",
    "title": "Update Executive Summary text for monthly/quarterly cadence",
    "description": "Rewrite summary to state latest closed month, refresh frequency (monthly/quarterly), and cite net cash flow direction plus count of cash-flow drivers surfaced.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json (Executive Summary text panel)",
    "effort": "tiny",
    "status": "pending"
  },
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
    "id": 60,
    "category": "dashboard-fix",
    "title": "Clean Executive Summary text",
    "description": "Remove foreign/garbled characters and restate summary in plain English for the selected month; ensure utf-8 content and template variables render cleanly.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json (Executive Summary text panel)",
    "effort": "tiny",
    "status": "pending"
  },
  {
    "id": 61,
    "category": "dashboard-fix",
    "title": "Use Grafana timepicker instead of custom time_window",
    "description": "Un-hide Grafana timepicker, wire panels to Grafana's global range, keep month selector for convenience, and remove/ignore the custom time_window variable so time range follows built-in picker.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; datasource queries using window_range CTE",
    "effort": "medium",
    "status": "pending"
  },
  {
    "id": 62,
    "category": "dashboard-fix",
    "title": "Refine AI Financial Insights tone",
    "description": "Remove the \"create basic savings plan\" suggestion; replace with offset-focused savings acknowledgement and higher-value insights (e.g., variance drivers, category anomalies).",
    "scope": "reporting.rpt_outflows_insights_dashboard (AI insights text) and grafana/provisioning/dashboards/executive-dashboard.json AI panel",
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
    "id": 64,
    "category": "dashboard-fix",
    "title": "Triage Emergency Fund and Family Essentials figures",
    "description": "Emergency fund coverage shows 187 months and Family Essentials shows 459; clarify definitions, cap or contextualize overly large values, and align labels to real-world meaning.",
    "scope": "reporting.rpt_monthly_budget_summary, reporting.rpt_family_essentials; grafana/provisioning/dashboards/executive-dashboard.json (Emergency Fund, Family Essentials panels)",
    "effort": "medium",
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
    "id": 66,
    "category": "dashboard-fix",
    "title": "Remove/replace Month-to-Date widget",
    "description": "MTD stats are misleading with quarterly refresh; hide or replace with last-closed-month metrics and trend context.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json (MTD panel)",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 21,
    "category": "dashboard-fix",
    "title": "Fix Family Essentials stat (latest month filter + fallback)",
    "description": "SQL: add WHERE budget_year_month = (SELECT month_key FROM selected_key) and COALESCE all spend columns to 0; keep ORDER BY budget_year_month DESC LIMIT 1 so latest closed month returns a row. Grafana (panel title 'Family Essentials (Last Month)' in executive-dashboard.json): set reduceOptions.values=true and fields='Total Essentials' so the stat shows the total, not an empty state.",
    "scope": "reporting.rpt_family_essentials; grafana/provisioning/dashboards/executive-dashboard.json (Family Essentials stat panel)",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 22,
    "category": "dashboard-fix",
    "title": "Correct Asset & Liability Snapshot sign logic",
    "description": "SQL (rpt_household_net_worth): compute total_assets = SUM(CASE WHEN account_type!='liability' THEN balance_abs ELSE 0 END), total_liabilities = SUM(CASE WHEN account_type='liability' THEN balance_abs ELSE 0 END); net_worth = total_assets - total_liabilities; debt_to_asset_ratio = total_liabilities/NULLIF(total_assets,0). Grafana (Asset & Liability Snapshot panel): keep unit currencyUSD; no negatives should appear for assets.",
    "scope": "reporting.rpt_household_net_worth; grafana/provisioning/dashboards/executive-dashboard.json (Asset & Liability Snapshot panel)",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 23,
    "category": "dashboard-fix",
    "title": "Restore Monthly Financial Snapshot income/expense values",
    "description": "SQL: source monthly_income = inflow_excl_transfers, monthly_expenses = outflow_excl_transfers from rpt_cash_flow_analysis for selected month; monthly_net_cash_flow = monthly_income - monthly_expenses; COALESCE fields to 0. Grafana panel 'Monthly Financial Snapshot': ensure fields map to monthly_income, monthly_expenses, monthly_net_cash_flow, monthly_total_savings (same as net cash flow) and keep unit currencyUSD.",
    "scope": "reporting.rpt_cash_flow_analysis; grafana/provisioning/dashboards/executive-dashboard.json (Monthly Financial Snapshot stat)",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 24,
    "category": "dashboard-fix",
    "title": "Return percent values in Savings & Expense Performance",
    "description": "SQL: output savings_rate_pct = ROUND(CASE WHEN total_income>0 THEN net_cash_flow/total_income*100 END,1), savings_rate_3m_pct same windowed, savings_rate_ytd_pct = ytd_net_cash_flow/NULLIF(ytd_income,0)*100, expense_ratio_pct = outflow_to_inflow_ratio*100. Grafana (Savings & Expense Performance bar gauge): set unit to percent (not percentunit), thresholds 5/10/20/30, min 0 max 100.",
    "scope": "reporting.rpt_monthly_budget_summary; grafana/provisioning/dashboards/executive-dashboard.json (Savings & Expense Performance)",
    "effort": "small",
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
    "id": 26,
    "category": "dashboard-fix",
    "title": "Make Data Quality Callouts numeric and actionable",
    "description": "SQL: return uncategorized_pct numeric (no % string) and uncategorized_amount; keep stale_accounts and unmatched_transfers. Grafana table: set uncategorized_pct unit percent, thresholds red>15, yellow>10; add link column to /d/transaction_analysis_dashboard?var_category=Uncategorized. Keep existing link to outflows_reconciliation.",
    "scope": "reporting.rpt_outflows_insights_dashboard; grafana/provisioning/dashboards/executive-dashboard.json (Data Quality Callouts)",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 27,
    "category": "dashboard-fix",
    "title": "Add actionability to Top Uncategorized Merchants",
    "description": "SQL: add contribution_pct = total_amount / (SELECT SUM(total_amount) FROM reporting.viz_uncategorized_transactions_with_original_memo) * 100; filter WHERE txn_count>=2 OR total_amount>=100; keep ORDER BY total_amount DESC LIMIT 10. Grafana table: add Contribution % column (unit percent, two decimals), add URL link per merchant to categorize flow (same target as existing script path).",
    "scope": "reporting.viz_uncategorized_transactions_with_original_memo; grafana/provisioning/dashboards/executive-dashboard.json (Top Uncategorized Merchants table)",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 28,
    "category": "dashboard-fix",
    "title": "Improve Week-to-Date Spending Pace readability",
    "description": "SQL: add pace_ratio = wtd_spending / NULLIF(expected_spend_to_date,0) * 100 and return expected_spend_to_date. Grafana stat: set main value to pace_ratio (unit percent, thresholds <90 green, 90–110 yellow, >110 red); show secondaries Week Spent, Weekly Budget, Daily Budget Left, Days Left; hide raw pace_status field.",
    "scope": "reporting.rpt_weekly_spending_pace; grafana/provisioning/dashboards/executive-dashboard.json (Week-to-Date Spending Pace stat)",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 29,
    "category": "dashboard-fix",
    "title": "Tighten Emergency Fund Coverage gauge",
    "description": "SQL: months_essential_expenses_covered = liquid_assets / NULLIF(essential_expenses_last_month,0); return coverage_status. Grafana gauge: set max 6, unit month, thresholds at 0/1/3/6 (red/orange/yellow/green), show status text as secondary label.",
    "scope": "reporting.rpt_emergency_fund_coverage; grafana/provisioning/dashboards/executive-dashboard.json (Emergency Fund Coverage gauge)",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 30,
    "category": "dashboard-fix",
    "title": "Replace MoM Cash table with drivers waterfall",
    "description": "SQL: for selected and previous month, calculate income_delta = curr.total_income - prev.total_income, expense_delta = -(curr.total_expenses - prev.total_expenses), transfers_delta = COALESCE(curr.internal_transfers,0) - COALESCE(prev.internal_transfers,0), net_delta = curr.net_cash_flow - prev.net_cash_flow; return ordered rows income, expense, transfers, net. Grafana: replace existing MoM Cash Changes table with waterfall visualization using these rows.",
    "scope": "reporting.rpt_monthly_budget_summary (plus internal_transfers source) and grafana/provisioning/dashboards/executive-dashboard.json (replace MoM Cash Changes panel)",
    "effort": "medium",
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
    "notes": "Use scripts/categorize_transactions.py interactive tool. 19 patterns (1004 transactions) categorized in previous session."
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
    "id": 3,
    "category": "family-insights",
    "title": "Add 'Family Essentials' cost panel to Executive dashboard",
    "description": "Create a single stat row showing monthly totals for: Childcare, Groceries, Kids Activities, Family Medical. These are the non-negotiable costs parents need to see first",
    "scope": "Grafana Executive dashboard + new SQL panel",
    "effort": "medium",
    "status": "done",
    "notes": "Created rpt_family_essentials.sql model and added 'Family Essentials (Last Month)' stat panel to Executive dashboard"
  },
  {
    "id": 4,
    "category": "emergency-fund",
    "title": "Add emergency fund coverage panel to Executive dashboard",
    "description": "Calculate months of essential expenses covered by liquid assets (target: 3-6 months). Show as gauge with red/yellow/green zones",
    "scope": "Grafana panel + SQL calculation",
    "effort": "small",
    "status": "done",
    "notes": "Created rpt_emergency_fund_coverage.sql model and added gauge panel to Executive dashboard with red/orange/yellow/green thresholds at 0/1/3/6 months"
  },
  {
    "id": 5,
    "category": "weekly-pacing",
    "title": "Add 'Week-to-Date Spending Pace' panel",
    "description": "Show current week spending vs weekly budget target (monthly budget / weeks in month). Include 'days remaining' and 'daily budget remaining' for easy mental math",
    "scope": "New Grafana panel on Executive or new Weekly Review dashboard",
    "effort": "medium",
    "status": "done",
    "notes": "Created rpt_weekly_spending_pace.sql model and added 'Week-to-Date Spending Pace' stat panel to Executive dashboard showing weekly budget, spending, and daily budget remaining"
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
    "id": 46,
    "category": "dashboard-fix",
    "title": "Resolve public dashboard 404 error",
    "description": "Grafana console shows 404 on GET /api/dashboards/uid/executive_dashboard/public-dashboards. Audit Public Dashboards/NG plugin config and share settings; either enable the feature with correct endpoint or disable the share toggle to avoid broken requests.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Grafana public dashboards/plugin settings",
    "effort": "small",
    "status": "pending",
    "notes": "Observed 2026-02-03 in Executive Financial Overview."
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
  }
]
