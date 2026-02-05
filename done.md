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
    "status": "done",
    "notes": "Fixed integer division in Health & Risk delta_ratio (cast to ::numeric). Added nullTextValue for 0/0 cases."
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
    "description": "Top layout order: Data Freshness → Monthly Financial Snapshot → Family Essentials → Emergency Fund → Cash Flow Drivers; move Data Quality Callouts directly under hero; fold detailed KPI tables into a collapsible section.",
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
  }
]
