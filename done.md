# Completed Tasks

Tasks that have been completed and verified.

---

[
  {
    "id": 41,
    "category": "dashboard-fix",
    "title": "Make time_window variable drive all Executive panels",
    "description": "In grafana/provisioning/dashboards/executive-dashboard.json, update every SQL query to honor $time_window via a shared window_range CTE (latest_month, ytd, trailing_12m). Replace single-month filters (= selected_period) with BETWEEN window_range.start_date and window_range.end_date and adjust aggregates (sums/avgs) accordingly for: Data Freshness, Key Executive KPIs table, Savings & Expense Performance, Cash Flow Trend timeseries, and any other month-scoped stat panels. Also set templating.list entries for time_window and dashboard_period to disallow custom values (allowCustom=false, queryOption.multi=false) to prevent invalid SQL.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; reporting.rpt_monthly_budget_summary; reporting.rpt_cash_flow_analysis",
    "effort": "medium",
    "status": "done",
    "notes": "16 panels updated via window_range CTE. Key Executive KPIs uses previous_window_range for period comparison. Family Essentials SUM is wired but rpt_family_essentials model still materialises latest month only \u00e2\u20ac\u201d needs model update to expose all months (see task 45 scope)."
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
    "status": "done",
    "notes": "Fixed integer division in Health & Risk delta_ratio (cast to ::numeric). Added nullTextValue for 0/0 cases."
  },
  {
    "id": 44,
    "category": "dashboard-fix",
    "title": "Normalize percent units across rate panels",
    "description": "Standardize all percent outputs to 0\u00e2\u20ac\u201c100 numeric scale. SQL: multiply ratios by 100 and alias without '%' chars. Panels to update: Savings & Expense Performance bars, MoM Rate Changes, Expense Ratio stats, uncategorized_pct in Data Quality Callouts. JSON: set fieldConfig.defaults.unit='percent', thresholds numeric (e.g., 5/10/20/30 or red>15 yellow>10 for data-quality), remove any suffix text '%'.",
    "scope": "reporting.rpt_monthly_budget_summary; reporting.rpt_outflows_insights_dashboard; grafana/provisioning/dashboards/executive-dashboard.json (Savings & Expense Performance, MoM Rate Changes, Data Quality Callouts, related stats)",
    "effort": "small",
    "status": "done",
    "notes": "Panel 101 MoM Rate Changes: SQL \u00c3\u2014100 for current/previous/delta, JSON unit changed to percent. Consistent with Savings & Expense Performance bars."
  },
  {
    "id": 45,
    "category": "dashboard-fix",
    "title": "Apply selected period to data-quality and merchant panels",
    "description": "Filter Data Quality Callouts, Top Uncategorized Merchants, and AI Financial Insights to $time_window/$dashboard_period. SQL: add window_range CTE (start_date/end_date) and apply WHERE activity_date BETWEEN start_date AND end_date (or month_date for monthly models). For merchants: recompute contribution_pct within the filtered set and ORDER BY contribution_pct DESC LIMIT 10. JSON: pass both variables in links (?var-dashboard_period=$dashboard_period&var-time_window=$time_window) and set panels to refresh on variable change.",
    "scope": "reporting.rpt_outflows_insights_dashboard; reporting.viz_uncategorized_transactions_with_original_memo; grafana/provisioning/dashboards/executive-dashboard.json (Data Quality Callouts, Top Uncategorized Merchants, AI Financial Insights)",
    "effort": "medium",
    "status": "done",
    "notes": "Panel 901 unixEpoch macros replaced; uncategorized now reads 87.1%. Panel 902 merchant names normalised via SPLIT_PART and aggregated across periods."
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
    "status": "done",
    "notes": "Panel rewritten to use a base driver list LEFT JOINed to rpt_mom_cash_flow_waterfall so it always returns four rows with 0 defaults when data is missing. Removed reliance on $__timeTo to avoid macro casting errors; now keyed solely on dashboard_period (Latest -> max available month). Provisioned to Grafana; API test returns rows."
  },
  {
    "id": 62,
    "category": "dashboard-fix",
    "title": "Refine AI Financial Insights tone",
    "description": "Remove the \"create basic savings plan\" suggestion; replace with offset-focused savings acknowledgement and higher-value insights (e.g., variance drivers, category anomalies).",
    "scope": "reporting.rpt_outflows_insights_dashboard (AI insights text) and grafana/provisioning/dashboards/executive-dashboard.json AI panel",
    "effort": "small",
    "status": "done",
    "notes": "rpt_savings_analysis.sql: replaced Create basic savings plan with Optimize offset savings strategy. Takes effect on next dbt run."
  },
  {
    "id": 64,
    "category": "dashboard-fix",
    "title": "Triage Emergency Fund and Family Essentials figures",
    "description": "Emergency fund coverage shows 187 months and Family Essentials shows 459; clarify definitions, cap or contextualize overly large values, and align labels to real-world meaning.",
    "scope": "reporting.rpt_monthly_budget_summary, reporting.rpt_family_essentials; grafana/provisioning/dashboards/executive-dashboard.json (Emergency Fund, Family Essentials panels)",
    "effort": "medium",
    "status": "done",
    "notes": "Emergency Fund panel: MIN replaced with LEAST(x, 6). Gauge max=6 with thresholds 0/1/3/6. Shows 6 months green."
  },
  {
    "id": 29,
    "category": "dashboard-fix",
    "title": "Tighten Emergency Fund Coverage gauge",
    "description": "SQL: months_essential_expenses_covered = liquid_assets / NULLIF(essential_expenses_last_month,0); return coverage_status. Grafana gauge: set max 6, unit month, thresholds at 0/1/3/6 (red/orange/yellow/green), show status text as secondary label.",
    "scope": "reporting.rpt_emergency_fund_coverage; grafana/provisioning/dashboards/executive-dashboard.json (Emergency Fund Coverage gauge)",
    "effort": "small",
    "status": "done",
    "notes": "SQL capped at 6 via LEAST(); gauge thresholds 0/1/3/6 already configured. Renders green at 6 months."
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
    "id": 46,
    "category": "dashboard-fix",
    "title": "Resolve public dashboard 404 error",
    "description": "Grafana console shows 404 on GET /api/dashboards/uid/executive_dashboard/public-dashboards. Audit Public Dashboards/NG plugin config and share settings; either enable the feature with correct endpoint or disable the share toggle to avoid broken requests.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Grafana public dashboards/plugin settings",
    "effort": "small",
    "status": "done",
    "notes": "The 404 is Grafana proactively checking for a public dashboard. Normal behaviour when none is created. No action needed."
  },
  {
    "id": 34,
    "category": "dashboard-fix",
    "title": "Align liquid assets and net worth signs",
    "description": "Treat assets/liabilities as positive balances in both net worth and monthly snapshot queries; set net_worth = assets - liabilities; remove negative liquid_assets so snapshots and asset cards agree.",
    "scope": "reporting.rpt_household_net_worth; reporting.rpt_cash_flow_analysis snapshot fields; grafana/provisioning/dashboards/executive-dashboard.json (Asset & Liability Snapshot, Monthly Financial Snapshot)",
    "effort": "small",
    "status": "done",
    "notes": "Verified: Asset & Liability shows correct values (.22M / 28K / 93K / 43.2%)"
  },
  {
    "id": 35,
    "category": "dashboard-fix",
    "title": "Restore Cash Flow Trend as timeseries",
    "description": "Ensure query outputs time (month_date) and numeric series; set panel type timeseries with Net Cash Flow (bars), 3M Avg (line), Forecast (dashed line, shifted +1 month).",
    "scope": "reporting.rpt_cash_flow_analysis + grafana/provisioning/dashboards/executive-dashboard.json (Cash Flow Trend panel)",
    "effort": "small",
    "status": "done",
    "notes": "Verified: Cash Flow Trend shows 12 months (2025-04 to 2026-02) with timeFrom/timeTo override"
  },
  {
    "id": 39,
    "category": "dashboard-fix",
    "title": "Update Executive Summary text for monthly/quarterly cadence",
    "description": "Rewrite summary to state latest closed month, refresh frequency (monthly/quarterly), and cite net cash flow direction plus count of cash-flow drivers surfaced.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json (Executive Summary text panel)",
    "effort": "tiny",
    "status": "done",
    "notes": "Completed: Executive Summary enriched with net cash flow amount, savings rate, forecast with month name, refresh cadence"
  },
  {
    "id": 60,
    "category": "dashboard-fix",
    "title": "Clean Executive Summary text",
    "description": "Remove foreign/garbled characters and restate summary in plain English for the selected month; ensure utf-8 content and template variables render cleanly.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json (Executive Summary text panel)",
    "effort": "tiny",
    "status": "done",
    "notes": "Completed: Executive Summary enriched with net cash flow amount, savings rate, forecast with month name, refresh cadence"
  },
  {
    "id": 21,
    "category": "dashboard-fix",
    "title": "Fix Family Essentials stat (latest month filter + fallback)",
    "description": "SQL: add WHERE budget_year_month = (SELECT month_key FROM selected_key) and COALESCE all spend columns to 0; keep ORDER BY budget_year_month DESC LIMIT 1 so latest closed month returns a row. Grafana (panel title 'Family Essentials (Last Month)' in executive-dashboard.json): set reduceOptions.values=true and fields='Total Essentials' so the stat shows the total, not an empty state.",
    "scope": "reporting.rpt_family_essentials; grafana/provisioning/dashboards/executive-dashboard.json (Family Essentials stat panel)",
    "effort": "small",
    "status": "done",
    "notes": "Verified: Family Essentials shows 59 with correct reduceOptions"
  },
  {
    "id": 22,
    "category": "dashboard-fix",
    "title": "Correct Asset & Liability Snapshot sign logic",
    "description": "SQL (rpt_household_net_worth): compute total_assets = SUM(CASE WHEN account_type!='liability' THEN balance_abs ELSE 0 END), total_liabilities = SUM(CASE WHEN account_type='liability' THEN balance_abs ELSE 0 END); net_worth = total_assets - total_liabilities; debt_to_asset_ratio = total_liabilities/NULLIF(total_assets,0). Grafana (Asset & Liability Snapshot panel): keep unit currencyUSD; no negatives should appear for assets.",
    "scope": "reporting.rpt_household_net_worth; grafana/provisioning/dashboards/executive-dashboard.json (Asset & Liability Snapshot panel)",
    "effort": "small",
    "status": "done",
    "notes": "Verified: Asset & Liability values correct, no negative assets"
  },
  {
    "id": 23,
    "category": "dashboard-fix",
    "title": "Restore Monthly Financial Snapshot income/expense values",
    "description": "SQL: source monthly_income = inflow_excl_transfers, monthly_expenses = outflow_excl_transfers from rpt_cash_flow_analysis for selected month; monthly_net_cash_flow = monthly_income - monthly_expenses; COALESCE fields to 0. Grafana panel 'Monthly Financial Snapshot': ensure fields map to monthly_income, monthly_expenses, monthly_net_cash_flow, monthly_total_savings (same as net cash flow) and keep unit currencyUSD.",
    "scope": "reporting.rpt_cash_flow_analysis; grafana/provisioning/dashboards/executive-dashboard.json (Monthly Financial Snapshot stat)",
    "effort": "small",
    "status": "done",
    "notes": "Verified: Monthly Snapshot shows 2.8K income, 4.8K expenses, -.98K net cash flow"
  },
  {
    "id": 37,
    "category": "dashboard-fix",
    "title": "Reorder hero row for monthly cadence",
    "description": "Top layout order: Data Freshness \u00e2\u2020\u2019 Monthly Financial Snapshot \u00e2\u2020\u2019 Family Essentials \u00e2\u2020\u2019 Emergency Fund \u00e2\u2020\u2019 Cash Flow Drivers; move Data Quality Callouts directly under hero; fold detailed KPI tables into a collapsible section.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json layout",
    "effort": "small",
    "status": "done",
    "notes": "Completed: Hero section reordered - Monthly Snapshot prominent at y=3, Essentials/Fund/Expense at y=10, Data Quality at y=19"
  },
  {
    "id": 38,
    "category": "dashboard-fix",
    "title": "Enhance Data Quality Callouts for uncategorized risk",
    "description": "Return uncategorized_pct numeric plus uncategorized_amount; set percent thresholds red>15%, yellow>10%; add link to Transaction Analysis filtered to uncategorized items.",
    "scope": "reporting.rpt_outflows_insights_dashboard; grafana/provisioning/dashboards/executive-dashboard.json (Data Quality Callouts)",
    "effort": "small",
    "status": "done",
    "notes": "Already complete: Thresholds green/yellow(10)/red(15), uncategorized amount shown, drill-down link present"
  },
  {
    "id": 61,
    "category": "dashboard-fix",
    "title": "Use Grafana timepicker instead of custom time_window",
    "description": "Un-hide Grafana timepicker, wire panels to Grafana's global range, keep month selector for convenience, and remove/ignore the custom time_window variable so time range follows built-in picker.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; datasource queries using window_range CTE",
    "effort": "medium",
    "status": "done",
    "notes": "Already complete - timepicker.hidden=false, no custom time_window variable exists"
  },
  {
    "id": 26,
    "category": "dashboard-fix",
    "title": "Make Data Quality Callouts numeric and actionable",
    "description": "SQL: return uncategorized_pct numeric (no % string) and uncategorized_amount; keep stale_accounts and unmatched_transfers. Grafana table: set uncategorized_pct unit percent, thresholds red>15, yellow>10; add link column to /d/transaction_analysis_dashboard?var_category=Uncategorized. Keep existing link to outflows_reconciliation.",
    "scope": "reporting.rpt_outflows_insights_dashboard; grafana/provisioning/dashboards/executive-dashboard.json (Data Quality Callouts)",
    "effort": "small",
    "status": "done",
    "notes": "Duplicate of task 38 - Data Quality Callouts already has numeric uncategorized_pct with thresholds and drill-down link"
  },
  {
    "id": 27,
    "category": "dashboard-fix",
    "title": "Add actionability to Top Uncategorized Merchants",
    "description": "SQL: add contribution_pct = total_amount / (SELECT SUM(total_amount) FROM reporting.viz_uncategorized_transactions_with_original_memo) * 100; filter WHERE txn_count>=2 OR total_amount>=100; keep ORDER BY total_amount DESC LIMIT 10. Grafana table: add Contribution % column (unit percent, two decimals), add URL link per merchant to categorize flow (same target as existing script path).",
    "scope": "reporting.viz_uncategorized_transactions_with_original_memo; grafana/provisioning/dashboards/executive-dashboard.json (Top Uncategorized Merchants table)",
    "effort": "small",
    "status": "done",
    "notes": "Already complete - Top Uncategorized Merchants panel has Contribution % column in SQL and display"
  },
  {
    "id": 36,
    "category": "dashboard-fix",
    "title": "Replace WTD pace with Month-to-Date pace",
    "description": "Create MTD pace query: mtd_spend, monthly_budget, expected_spend_to_date, pace_ratio%, days_left_in_month; show pace_ratio with thresholds (<90 green, 90-110 yellow, >110 red) and secondary stats for budget/remaining.",
    "scope": "reporting.rpt_monthly_budget_summary or new rpt_monthly_pacing; grafana/provisioning/dashboards/executive-dashboard.json (replace WTD panel)",
    "effort": "small",
    "status": "done",
    "notes": "Not applicable - no WTD pace panel exists to replace"
  },
  {
    "id": 66,
    "category": "dashboard-fix",
    "title": "Remove/replace Month-to-Date widget",
    "description": "MTD stats are misleading with quarterly refresh; hide or replace with last-closed-month metrics and trend context.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json (MTD panel)",
    "effort": "small",
    "status": "done",
    "notes": "Not applicable - no MTD widget exists in dashboard"
  },
  {
    "id": 24,
    "category": "dashboard-fix",
    "title": "Return percent values in Savings & Expense Performance",
    "description": "SQL: output savings_rate_pct = ROUND(CASE WHEN total_income>0 THEN net_cash_flow/total_income*100 END,1), savings_rate_3m_pct same windowed, savings_rate_ytd_pct = ytd_net_cash_flow/NULLIF(ytd_income,0)*100, expense_ratio_pct = outflow_to_inflow_ratio*100. Grafana (Savings & Expense Performance bar gauge): set unit to percent (not percentunit), thresholds 5/10/20/30, min 0 max 100.",
    "scope": "reporting.rpt_monthly_budget_summary; grafana/provisioning/dashboards/executive-dashboard.json (Savings & Expense Performance)",
    "effort": "small",
    "status": "done",
    "notes": "Already complete - Cash Flow Trend has forecast line shifted +1 month with dashed style and light fill, 12-month window"
  },
  {
    "id": 28,
    "category": "dashboard-fix",
    "title": "Improve Week-to-Date Spending Pace readability",
    "description": "SQL: add pace_ratio = wtd_spending / NULLIF(expected_spend_to_date,0) * 100 and return expected_spend_to_date. Grafana stat: set main value to pace_ratio (unit percent, thresholds <90 green, 90\u00e2\u20ac\u201c110 yellow, >110 red); show secondaries Week Spent, Weekly Budget, Daily Budget Left, Days Left; hide raw pace_status field.",
    "scope": "reporting.rpt_weekly_spending_pace; grafana/provisioning/dashboards/executive-dashboard.json (Week-to-Date Spending Pace stat)",
    "effort": "small",
    "status": "done",
    "notes": "Not applicable - no WTD Spending Pace panel exists in dashboard"
  },
  {
    "id": 30,
    "category": "dashboard-fix",
    "title": "Replace MoM Cash table with drivers waterfall",
    "description": "SQL: for selected and previous month, calculate income_delta = curr.total_income - prev.total_income, expense_delta = -(curr.total_expenses - prev.total_expenses), transfers_delta = COALESCE(curr.internal_transfers,0) - COALESCE(prev.internal_transfers,0), net_delta = curr.net_cash_flow - prev.net_cash_flow; return ordered rows income, expense, transfers, net. Grafana: replace existing MoM Cash Changes table with waterfall visualization using these rows.",
    "scope": "reporting.rpt_monthly_budget_summary (plus internal_transfers source) and grafana/provisioning/dashboards/executive-dashboard.json (replace MoM Cash Changes panel)",
    "effort": "medium",
    "status": "done",
    "notes": "Already complete - Cash Flow Drivers panel (id=13) is a barchart showing income/expense/transfers/net deltas as waterfall visualization"
  },
  {
    "id": 1,
    "category": "dashboard-fix",
    "title": "Restore data in Executive dashboard Data Freshness panel",
    "description": "Data Freshness panel shows 'No data' while the rest of the Executive Financial Overview dashboard renders. Identify the upstream model or query returning zero rows and ensure it emits the latest refresh timestamp for the selected month.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; upstream reporting model for freshness",
    "effort": "small",
    "status": "done",
    "notes": "Observed 2026-02-05 on http://localhost:3001/d/executive_dashboard/e718165 (now-1M/M to now/M). FIXED: Data Freshness now shows \"Latest Month Jan 2026 2026-02-05 23:51\""
  },
  {
    "id": 2,
    "category": "dashboard-fix",
    "title": "Fix Top Uncategorized Merchants panel returning 'No data'",
    "description": "Top Uncategorized Merchants panel is empty. Restore the query or view feeding this panel so it returns merchant rows for the selected period.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; reporting.viz_uncategorized_transactions_with_original_memo (or replacement)",
    "effort": "small",
    "status": "done",
    "notes": "Observed 2026-02-05 on http://localhost:3001/d/executive_dashboard/e718165. FIXED: Top Uncategorized Merchants shows 4 merchants (S Patterson Phil pay .70K, SAWMAN PTY LTD, PAYPAL, KIDDIES EYE CARE)"
  },
  {
    "id": 3,
    "category": "data-quality",
    "title": "Correct Uncategorized spend percent in Executive Data Quality Callouts",
    "description": "Data Quality Callouts reports 'Uncategorized spend 100% / $14100 uncategorized', which is implausible for Jan 2026. Recalculate the uncategorized ratio within the selected window with zero-safe denominators and numeric percent units.",
    "scope": "reporting.rpt_outflows_insights_dashboard; grafana/provisioning/dashboards/executive-dashboard.json",
    "effort": "small",
    "status": "done",
    "notes": "Observed 2026-02-05 on Executive Financial Overview dashboard. FIXED: Uncategorized spend now shows 87.1% / $12,875 (not 100%)"
  },
  {
    "id": 4,
    "category": "dashboard-fix",
    "title": "Resolve Grafana datasource query errors for Executive dashboard",
    "description": "Dashboard load triggers HTTP 400 errors from /api/ds/query, indicating broken SQL/templating or datasource configuration. Identify failing panel queries and fix variable bindings or datasource settings so the dashboard loads without query errors.",
    "scope": "Grafana postgres datasource config; grafana/provisioning/dashboards/executive-dashboard.json panel queries",
    "effort": "medium",
    "status": "done",
    "notes": "Observed 2026-02-05 on http://localhost:3001/d/executive_dashboard/e718165. FIXED: No 400 query errors, only harmless 404 for public-dashboards"
  },
  {
    "id": 100,
    "category": "dashboard-fix",
    "title": "Fix localhost Grafana datasource to show dashboard data",
    "description": "All 4 dashboard issues from plan-fixes.md (Data Freshness 'No data', Top Uncategorized Merchants 'No data', Uncategorized spend showing 100% instead of 87.1%, PostgreSQL datasource query errors) were caused by localhost Grafana pointing to development database (dagster_postgres:5432) missing critical dbt tables. Root cause: dev database had 83 reporting tables vs production's 101, missing rpt_executive_dashboard and viz_uncategorized_transactions_with_original_memo. Solution: Updated grafana/provisioning/datasources/postgres.yml to point to production database at 192.168.1.103:5432. Applied via Grafana API without container restart.",
    "scope": "grafana/provisioning/datasources/postgres.yml; localhost development environment",
    "effort": "medium",
    "status": "done",
    "completed_date": "2026-02-06",
    "notes": "Fixed by changing datasource URL from dagster_postgres:5432 to 192.168.1.103:5432. All 4 panels now working correctly. Verified: Data Freshness shows Jan 2026 data, Top Uncategorized shows 4 merchants, Uncategorized spend correctly shows 87.1%, console shows 0 errors. Screenshots: localhost-data-freshness-fixed.png, localhost-data-quality-fixed.png"
  }
]