# Family Finance Dashboard Roadmap

## Strategic Direction

The current dashboard suite provides comprehensive financial metrics but is optimized for detailed analysis rather than the quick, actionable insights needed by busy parents with three young children. The immediate priority is reducing the 38.7% uncategorized spend to under 15% so that category-level insights become trustworthy, then building family-specific views that surface childcare costs, grocery trends, and emergency fund progress prominently. Once the data foundation is solid, we'll add weekly pacing indicators and a simplified "Parent Dashboard" that answers "are we on track this week?" in under 30 seconds.

The second phase focuses on forward-looking features: upcoming recurring bills, seasonal expense preparation (school terms, holidays, sports registrations), and education savings goal tracking. Mobile dashboards will be enhanced with family-specific quick-glance panels so parents can check finances while managing morning routines. Throughout, the emphasis is on reducing cognitive load—surfacing only what matters this week rather than overwhelming with historical analysis.

---

## Status Notes

- On 2026-02-21, tasks 46-56 were completed by another LLM and moved to `done.md`.

## Concrete Tasks (Priority Order)

[
  {
    "id": 42,
    "category": "dashboard-fix",
    "title": "Sync dashboard time picker with selected period",
    "description": "Ensure the Grafana dashboard time range follows the chosen month in $dashboard_period: set timepicker.hidden=true (dashboard-level) and programmatically set panel queries to use the selected period window instead of the URL time range now-1M/M..now/M. Prevents mismatches where panels show the selected month but the global range stays on the previous one.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json (timepicker block, defaults); reporting queries already windowed after task 41",
    "effort": "small",
    "status": "done",
    "notes": "Verified complete against origin/main dashboard/models on 2026-02-21."
  },
  {
    "id": 43,
    "category": "dashboard-fix",
    "title": "Zero-safe deltas and ratios in Executive KPI tables",
    "description": "Guard division by zero and missing previous periods in Net Cash Flow and Forecast rows. SQL template: delta_ratio = CASE WHEN COALESCE(prev,0)=0 AND COALESCE(curr,0)=0 THEN 0 WHEN COALESCE(prev,0)=0 THEN NULL ELSE (curr-prev)/NULLIF(ABS(prev),0) END; delta_value = curr - COALESCE(prev,0). Apply the same logic to MoM Rate Changes. In JSON: set field.displayMode to 'color-text', nullValueMode='connected', and add 'text: n/a' override when value is null; keep percent unit.",
    "scope": "reporting.rpt_monthly_budget_summary; grafana/provisioning/dashboards/executive-dashboard.json (Key Executive KPIs, Month-over-Month Rate Changes tables)",
    "effort": "small",
    "status": "done",
    "notes": "Verified complete against origin/main dashboard/models on 2026-02-21."
  },
  {
    "id": 44,
    "category": "dashboard-fix",
    "title": "Normalize percent units across rate panels",
    "description": "Standardize all percent outputs to 0–100 numeric scale. SQL: multiply ratios by 100 and alias without '%' chars. Panels to update: Savings & Expense Performance bars, MoM Rate Changes, Expense Ratio stats, uncategorized_pct in Data Quality Callouts. JSON: set fieldConfig.defaults.unit='percent', thresholds numeric (e.g., 5/10/20/30 or red>15 yellow>10 for data-quality), remove any suffix text '%'.",
    "scope": "reporting.rpt_monthly_budget_summary; reporting.rpt_outflows_insights_dashboard; grafana/provisioning/dashboards/executive-dashboard.json (Savings & Expense Performance, MoM Rate Changes, Data Quality Callouts, related stats)",
    "effort": "small",
    "status": "done",
    "notes": "Verified complete against origin/main dashboard/models on 2026-02-21."
  },
  {
    "id": 45,
    "category": "dashboard-fix",
    "title": "Apply selected period to data-quality and merchant panels",
    "description": "Filter Data Quality Callouts, Top Uncategorized Merchants, and AI Financial Insights to $time_window/$dashboard_period. SQL: add window_range CTE (start_date/end_date) and apply WHERE activity_date BETWEEN start_date AND end_date (or month_date for monthly models). For merchants: recompute contribution_pct within the filtered set and ORDER BY contribution_pct DESC LIMIT 10. JSON: pass both variables in links (?var-dashboard_period=$dashboard_period&var-time_window=$time_window) and set panels to refresh on variable change.",
    "scope": "reporting.rpt_outflows_insights_dashboard; reporting.viz_uncategorized_transactions_with_original_memo; grafana/provisioning/dashboards/executive-dashboard.json (Data Quality Callouts, Top Uncategorized Merchants, AI Financial Insights)",
    "effort": "medium",
    "status": "done",
    "notes": "Verified complete against origin/main dashboard/models on 2026-02-21."
  },
  {
    "id": 31,
    "category": "dashboard-fix",
    "title": "Fix Monthly Income pull in Executive Snapshot",
    "description": "Use inflow_excl_transfers from reporting.rpt_cash_flow_analysis for selected month (COALESCE to 0) so Monthly Income is not $0; ensure datasource UID matches Postgres and join only on latest/selected month key.",
    "scope": "reporting.rpt_cash_flow_analysis; grafana/provisioning/dashboards/executive-dashboard.json (Monthly Financial Snapshot stat)",
    "effort": "small",
    "status": "done",
    "notes": "Verified complete against origin/main dashboard/models on 2026-02-21."
  },
  {
    "id": 32,
    "category": "dashboard-fix",
    "title": "Return real percentages in Savings & Expense Performance",
    "description": "Multiply ratios by 100 with divide-by-zero guards: savings_rate_pct, savings_rate_3m_pct, savings_rate_ytd_pct, expense_ratio_pct; set Grafana unit=percent and thresholds 5/10/20/30 so values no longer show 0%.",
    "scope": "reporting.rpt_monthly_budget_summary; grafana/provisioning/dashboards/executive-dashboard.json (Savings & Expense Performance bar gauge)",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 33,
    "category": "dashboard-fix",
    "title": "Make Cash Flow Drivers panel always return rows",
    "description": "In MoM drivers query, select current and previous month even if prior is missing by defaulting to 0 rows; compute income_delta, expense_delta, transfers_delta, net_delta; ensure datasource UID is valid to stop 'No data'.",
    "scope": "reporting.rpt_monthly_budget_summary (plus transfers source); grafana/provisioning/dashboards/executive-dashboard.json (Cash Flow Drivers panel)",
    "effort": "small",
    "status": "pending"
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
    "status": "done",
    "notes": "Verified complete against origin/main dashboard/models on 2026-02-21."
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
    "status": "done",
    "notes": "Verified complete against origin/main dashboard/models on 2026-02-21."
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
  }
]

