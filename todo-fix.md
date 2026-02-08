# Dashboard Fix Tasks

[
  {
    "id": 23,
    "title": "Backfill or relabel stale Net Worth headline month",
    "scope": "grafana/provisioning/dashboards/04-household-net-worth-analysis.json",
    "description": "Net worth headline recency lags other dashboards; backfill data or clearly label staleness.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "completed",
    "notes": "Completed 2026-02-08: relabeled headline as last complete month and added explicit staleness status in Data Freshness."
  },
  {
    "id": 24,
    "priority": 6,
    "category": "dashboard-fix",
    "title": "Add cross-dashboard schema compatibility layer for renamed reporting columns",
    "description": "Multiple dashboards are breaking due to model/schema drift (`total_essential_expenses`, `uncategorized`, missing legacy relations). Introduce a compatibility layer (views or standardized aliases) to decouple dashboard SQL from frequent model renames.",
    "scope": "reporting schema compatibility views; dashboards 01/07/08",
    "effort": "medium",
    "status": "completed",
    "notes": "Completed 2026-02-08: added reporting compat views for renamed columns (`uncategorized`/`uncategorized_amount`, `total_essential_expenses`/`total_family_essentials`) and rewired dashboards 01/08 to compat relations; validated 01/07/08 with zero failing panels."
  },
  {
    "id": 59,
    "title": "Finish Amazon schema migration beyond table rename",
    "scope": "grafana/provisioning/dashboards/17-amazon-spending-analysis.json",
    "description": "Dashboard 17 still has residual legacy field/join assumptions despite table rename.",
    "category": "dashboard-fix",
    "effort": "medium",
    "status": "completed",
    "notes": "Completed 2026-02-08: removed legacy `fct_transactions + dim_categories.store='Amazon'` dependency from dashboard queries; migrated to enhanced relations with resilient Amazon matching (store OR memo/description) and validated dashboard 17 with zero failing panels."
  },
  {
    "id": 60,
    "title": "Ensure reporting compat views are materialized in active environment",
    "scope": "pipeline_personal_finance/dbt_finance/models/reporting/compat/*",
    "description": "Compatibility relations referenced by historical SQL are absent in runtime schema.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "completed",
    "notes": "Completed 2026-02-08: compat views materialized and granted in active Grafana-connected Postgres (`192.168.1.103`) for runtime availability."
  },
  {
    "status": "pending",
    "notes": "Observed 2026-02-07 during Playwright runs across wide resolutions.",
    "scope": "Grafana dashboard JSON field options/mappings across dashboards 02-16",
    "category": "dashboard-fix",
    "effort": "medium",
    "id": 77,
    "title": "Eliminate recurring frontend console errors during dashboard navigation",
    "description": "Wide-screen traversal repeatedly logs client-side errors (invalid regex in build 322 and enum \"value\" mapping errors) which may hide real panel issues and degrade trust. Identify offending panel options/mappings and normalize to Grafana-supported values."
  },
  {
    "id": 78,
    "title": "Enforce atomic commit scope for dashboard changes",
    "scope": "git workflow and dashboard change process",
    "description": "Large mixed commits are obscuring intent and increasing regression risk. Enforce commit hygiene so rename-only, logic-only, and artifact-only changes are separated.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "in_progress",
    "notes": "In progress 2026-02-07: added atomic-scope guidance to `.github/pull_request_template.md`; hard enforcement remains process-based."
  },
  {
    "id": 80,
    "title": "Fix Account Performance runtime SQL macro errors",
    "scope": "grafana/provisioning/dashboards/11-account-performance.json",
    "description": "Panels 1, 3, 4, 5, and 7 fail due to boolean/type macro misuse (period_date/year_month expressions). Correct WHERE clauses and validate each panel renders.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "completed",
    "notes": "Completed 2026-02-08: replaced fragile macro filters on `period_date`/`year_month` with explicit date bounds using `$__timeFrom/$__timeTo`, and hardened latest-month snapshot selection. Validated dashboard 11 with zero failing panels."
  },
  {
    "id": 81,
    "title": "Normalize Account Performance UX semantics and currency",
    "scope": "grafana/provisioning/dashboards/11-account-performance.json",
    "description": "Replace technical panel names, switch units to AUD, and add explicit scope labels for latest-month vs history panels.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "completed",
    "notes": "Completed 2026-02-08: switched dashboard 11 currency units to AUD and renamed key panels to explicitly denote history vs latest-month scope."
  },
  {
    "id": 82,
    "title": "Harden Account Performance null/stale behaviors",
    "scope": "grafana/provisioning/dashboards/11-account-performance.json",
    "description": "Add no-row fallbacks for last-month panels, stale-data warnings, and timezone/cadence metadata in Data Freshness.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "completed",
    "notes": "Completed 2026-02-08: added no-row fallback for latest-month balances, added staleness status + timezone + expected cadence metadata in Data Freshness, and revalidated dashboard 11 with zero failing panels."
  },
  {
    "id": 83,
    "title": "Remove hardcoded projection constants in Financial Projections",
    "scope": "grafana/provisioning/dashboards/12-financial-projections.json",
    "description": "Replace hardcoded `2022-01-01`, fixed `projection_month = 12`, and static sensitivity assumptions with parameterized logic and safe fallbacks.",
    "category": "dashboard-fix",
    "effort": "medium",
    "status": "pending"
  },
  {
    "id": 84,
    "title": "Improve Financial Projections interpretability metadata",
    "scope": "grafana/provisioning/dashboards/12-financial-projections.json",
    "description": "Add timezone in freshness output, expose calibration data-through month, and clarify scenario labels for non-technical users.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 85,
    "title": "Resolve Year-over-Year dashboard semantic ambiguity",
    "scope": "grafana/provisioning/dashboards/13-year-over-year-comparison.json",
    "description": "Fix mixed units/scale ambiguity, reduce duplicated narrative panels, and clearly indicate complete-year handling in annual charts.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 86,
    "title": "Standardize Year-over-Year dashboard formatting and freshness context",
    "scope": "grafana/provisioning/dashboards/13-year-over-year-comparison.json",
    "description": "Switch currency to AUD, add timezone/cadence, and ensure yearly selection context is shown in panel titles.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 87,
    "title": "Correct Four-Year comparison metric scaling and sparse-data handling",
    "scope": "grafana/provisioning/dashboards/14-four-year-financial-comparison.json",
    "description": "Fix savings-rate scale mismatch, add divide-by-zero safety messaging, and show completeness indicators when fewer than four years are used.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 88,
    "title": "Fix Mortgage Payoff model assumptions and scenario transparency",
    "scope": "grafana/provisioning/dashboards/15-mortgage-payoff.json",
    "description": "Document and improve payoff assumptions, remove brittle `homeloan` naming dependency, and align sensitivity logic with actual interest-rate inputs.",
    "category": "dashboard-fix",
    "effort": "medium",
    "status": "pending"
  },
  {
    "id": 89,
    "title": "Make Grocery Spending dashboard data model configurable",
    "scope": "grafana/provisioning/dashboards/16-grocery-spending-analysis.json",
    "description": "Replace static budget target values, normalize AUD units, and reduce duplicated trend panels that dilute decision clarity.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 90,
    "title": "Repair Amazon Spending dashboard structural integrity",
    "scope": "grafana/provisioning/dashboards/17-amazon-spending-analysis.json",
    "description": "Eliminate duplicate panel IDs, remove hardcoded year ranges from titles/queries, and standardize freshness/context metadata.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 91,
    "title": "Adapt Executive Overview mobile dashboard for wide-screen rendering",
    "scope": "grafana/provisioning/dashboards/18-executive-overview-mobile.json",
    "description": "Adjust panel sizing/grouping for ultrawide viewports and normalize mixed-unit KPI presentation for desktop embedding.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 92,
    "title": "Improve Spending & Categories mobile dashboard consistency",
    "scope": "grafana/provisioning/dashboards/19-spending-categories-mobile.json",
    "description": "Normalize AUD units, remove redundant large-transaction panels, and clarify category hierarchy and legend semantics.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 93,
    "title": "Clarify Cash Flow & Budget mobile KPI definitions",
    "scope": "grafana/provisioning/dashboards/20-cash-flow-budget-mobile.json",
    "description": "Add explicit period labels, denominator definitions for ratio gauges, and fallback messages when source rows are missing.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 94,
    "title": "Fix 23-mobile projection query returning only half-year per scenario",
    "scope": "grafana/provisioning/dashboards/23-projections-analysis-mobile.json; panel id 1",
    "description": "`LIMIT 12` is applied to row-level scenario data where each date appears twice (full_time and part_time rows), which can truncate series to roughly 6 months per scenario. Pivot/group by date first or increase/query by projection month index.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending",
    "notes": "Found via Playwright MCP on 2026-02-07 at 3440x1440."
  },
  {
    "id": 95,
    "title": "Correct unit/type mismatch in 23-mobile scenario averages table",
    "scope": "grafana/provisioning/dashboards/23-projections-analysis-mobile.json; panel id 2",
    "description": "Table defaults to currency unit while `Avg Savings Rate` is a ratio. Playwright shows values rendered like `-$2.91`, indicating semantic/unit mismatch and likely upstream scale error.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending",
    "notes": "Found via Playwright MCP on 2026-02-07 at 3440x1440."
  },
  {
    "id": 96,
    "title": "Align 23-mobile YTD labels with actual comparison window",
    "scope": "grafana/provisioning/dashboards/23-projections-analysis-mobile.json; panel id 5",
    "description": "Panel title says `Current YTD vs Previous YTD` but query uses annual fields from year-over-year table, producing misleading extreme deltas. Use true same-period YTD values or relabel as annual comparison.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending",
    "notes": "Found via Playwright MCP on 2026-02-07 at 3440x1440."
  },
  {
    "id": 97,
    "title": "Fix 21-mobile Performance Metrics table unit overrides",
    "scope": "grafana/provisioning/dashboards/21-savings-performance-mobile.json; panel id 9",
    "description": "`Savings Rate` row in Month-over-Month table is rendered as currency (`$0`) instead of percent, indicating missing field-level override or mixed-schema output formatting.",
    "category": "dashboard-fix",
    "effort": "tiny",
    "status": "pending",
    "notes": "Found via Playwright MCP on 2026-02-07 at 3440x1440."
  },
  {
    "id": 98,
    "title": "Normalize liabilities sign conventions in 22-mobile KPI presentation",
    "scope": "grafana/provisioning/dashboards/22-assets-networth-mobile.json; panels 3 and 5",
    "description": "`Total Liabilities` is displayed as negative currency while table `Change` on liabilities can appear positive for debt reduction. Clarify sign semantics and present debt magnitude consistently.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending",
    "notes": "Found via Playwright MCP on 2026-02-07 at 3440x1440."
  },
  {
    "id": 99,
    "title": "Add timezone and refresh cadence to mobile Data Freshness panels 21-23",
    "scope": "grafana/provisioning/dashboards/21-savings-performance-mobile.json; grafana/provisioning/dashboards/22-assets-networth-mobile.json; grafana/provisioning/dashboards/23-projections-analysis-mobile.json",
    "description": "Freshness tables show date/time but no timezone or expected update cadence, making recency confidence weak for mobile review flows.",
    "category": "dashboard-fix",
    "effort": "tiny",
    "status": "pending",
    "notes": "Found via Playwright MCP on 2026-02-07 at 3440x1440."
  },
  {
    "id": 100,
    "title": "Replace technical account labels in 22-mobile account table",
    "scope": "grafana/provisioning/dashboards/22-assets-networth-mobile.json; panel id 5",
    "description": "Account names like `BillsBillsBills` and `Homeloan` reduce readability and trust for non-technical users. Map to user-facing labels or aliases in SQL/view layer.",
    "category": "dashboard-fix",
    "effort": "tiny",
    "status": "pending",
    "notes": "Found via Playwright MCP on 2026-02-07 at 3440x1440."
  },
  {
    "id": 102,
    "title": "Fix incomplete drilldown links in Executive Financial Overview tables",
    "scope": "grafana/provisioning/dashboards/01-executive-financial-overview-aud.json; panels 901 and 902",
    "description": "Playwright shows link targets ending with incomplete query strings (e.g., `/d/outflows_reconciliation?` and `/d/transaction_analysis_dashboard?var_category=Uncategorized&`). Ensure links include required variable values and clean URL formatting.",
    "category": "dashboard-fix",
    "effort": "tiny",
    "status": "pending",
    "notes": "Found via Playwright MCP on 2026-02-07 at 3440x1440."
  },
  {
    "id": 103,
    "title": "Add percent unit/label clarity to Executive Data Quality Callouts",
    "scope": "grafana/provisioning/dashboards/01-executive-financial-overview-aud.json; panel 901",
    "description": "`Uncategorized spend` value is displayed as `29.1` without `%` suffix in the callout table, which is ambiguous. Apply explicit percent formatting and label.",
    "category": "dashboard-fix",
    "effort": "tiny",
    "status": "pending",
    "notes": "Found via Playwright MCP on 2026-02-07 at 3440x1440."
  },
  {
    "id": 104,
    "title": "Disambiguate Monthly Savings vs Net Cash Flow in executive KPI row",
    "scope": "grafana/provisioning/dashboards/01-executive-financial-overview-aud.json; Monthly Financial Snapshot panel",
    "description": "Dashboard presents both `Net Cash Flow` and `Monthly Savings` with identical values, which appears duplicative. Either distinguish definitions or collapse to one metric.",
    "category": "dashboard-fix",
    "effort": "tiny",
    "status": "pending",
    "notes": "Found via Playwright MCP on 2026-02-07 at 3440x1440."
  },
  {
    "id": 105,
    "title": "Close remaining decision gaps in Executive dashboard headline section",
    "scope": "grafana/provisioning/dashboards/01-executive-financial-overview-aud.json",
    "description": "Two panels still render `No data` in Playwright and headline guidance is split across multiple blocks. Ensure all top-row cards resolve with fallback text, and add one explicit `Top 3 actions this month` panel to make the dashboard immediately decision-driven.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending",
    "notes": "Found via Playwright MCP on 2026-02-08 during dashboards 01-10 review."
  },
  {
    "id": 106,
    "title": "Improve Savings Analysis readability and actionability",
    "scope": "grafana/provisioning/dashboards/05-savings-analysis.json",
    "description": "Savings dashboard exposes technical field labels (e.g. `total_savings_rate_percent`) and weak action cues. Replace technical labels with user-facing names, add target-band color semantics, and include a short `what to do next` panel tied to current savings rate.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending",
    "notes": "Found via Playwright MCP on 2026-02-08 during dashboards 01-10 review."
  },
  {
    "id": 107,
    "title": "Refactor Category Spending dashboard for faster decisions",
    "scope": "grafana/provisioning/dashboards/06-category-spending-analysis.json",
    "description": "Dashboard is informative but text-heavy and lacks a concise control surface. Add a compact `largest controllable overruns` table with expected monthly impact, simplify instruction copy, and normalize panel naming for cleaner executive scanability.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending",
    "notes": "Found via Playwright MCP on 2026-02-08 during dashboards 01-10 review."
  },
  {
    "id": 108,
    "title": "Add explicit action recommendations to Expense Performance",
    "scope": "grafana/provisioning/dashboards/07-expense-performance-analysis.json",
    "description": "Current panels describe performance but do not translate driver values into concrete decisions. Add threshold-based recommendation rows (cut/hold/watch), include expected impact estimates, and prioritize the top 1-2 categories for intervention.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending",
    "notes": "Found via Playwright MCP on 2026-02-08 during dashboards 01-10 review."
  },
  {
    "id": 109,
    "title": "Fix Outflows Insights data failures and harden empty states",
    "scope": "grafana/provisioning/dashboards/08-outflows-insights.json",
    "description": "Playwright shows 8 `No data` panels and datasource request failures, making the dashboard non-actionable. Repair broken SQL/field references, validate all key panels return rows, and add explicit fallback messages when a period has no transactions.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending",
    "notes": "Found via Playwright MCP on 2026-02-08 during dashboards 01-10 review."
  },
  {
    "id": 110,
    "title": "Elevate Transaction Analysis from descriptive to prescriptive",
    "scope": "grafana/provisioning/dashboards/09-transaction-analysis.json",
    "description": "Dashboard is clean but mostly descriptive. Add an action queue panel (`top uncategorized to fix`, `new recurring merchants to review`, `high-value anomalies`) with clear thresholds and drilldown links so users know exactly what to do next.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending",
    "notes": "Found via Playwright MCP on 2026-02-08 during dashboards 01-10 review."
  },
  {
    "id": 111,
    "title": "Make Financial Reconciliation decision-oriented for non-technical users",
    "scope": "grafana/provisioning/dashboards/10-financial-reconciliation.json",
    "description": "Dashboard currently surfaces FAIL signals without clear remediation path. Add severity ranking, likely root-cause hints, and owner/action columns per failed check so users can quickly triage and resolve data quality blockers.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending",
    "notes": "Found via Playwright MCP on 2026-02-08 during dashboards 01-10 review."
  },
  {
    "id": 112,
    "title": "Harden Budget Adjustments panel empty-state behavior for CI smoke checks",
    "scope": "grafana/provisioning/dashboards/03-monthly-budget-summary.json; panel `Budget Adjustments for Next Month`; scripts/check_grafana_dashboards.py",
    "description": "Dashboard 03 panel can validly return zero rows in some months, but smoke checks currently treat empty results as failure. Add panel-level fallback row/message or checker allowlist semantics so valid empty states do not break gated CI.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending",
    "notes": "Found in commit review on 2026-02-08 after running checker with `--dashboard-range 1-23 --schema-validate`."
  },
  {
    "id": 113,
    "title": "Reconcile done.md completion claims with current dashboard lint reality",
    "scope": "done.md; todo-fix.md; tasks 73-76 and related dashboard panels",
    "description": "Tasks 73-76 are marked done, but current checker output still reports overflow warnings on the same dashboards/panels. Re-verify each claim, either close lint gaps or move tasks back to pending with updated evidence.",
    "category": "dashboard-fix",
    "effort": "tiny",
    "status": "pending",
    "notes": "Found in commit review on 2026-02-08; mismatch observed between `done.md` and current lint output."
  },
  {
    "id": 114,
    "title": "Burn down remaining markdown overflow lint warnings across dashboards 01-17",
    "scope": "grafana/provisioning/dashboards/01-executive-financial-overview-aud.json; grafana/provisioning/dashboards/02-cash-flow-analysis.json; grafana/provisioning/dashboards/03-monthly-budget-summary.json; grafana/provisioning/dashboards/04-household-net-worth-analysis.json; grafana/provisioning/dashboards/05-savings-analysis.json; grafana/provisioning/dashboards/06-category-spending-analysis.json; grafana/provisioning/dashboards/07-expense-performance-analysis.json; grafana/provisioning/dashboards/08-outflows-insights.json; grafana/provisioning/dashboards/09-transaction-analysis.json; grafana/provisioning/dashboards/10-financial-reconciliation.json; grafana/provisioning/dashboards/11-account-performance.json; grafana/provisioning/dashboards/12-financial-projections.json; grafana/provisioning/dashboards/13-year-over-year-comparison.json; grafana/provisioning/dashboards/14-four-year-financial-comparison.json; grafana/provisioning/dashboards/15-mortgage-payoff.json; grafana/provisioning/dashboards/17-amazon-spending-analysis.json",
    "description": "Current checker reports 22 lint warnings (mostly markdown text overflow) in dashboards touched by recent commits. Reduce copy, resize panels, or split sections so guidance text is readable at wide resolutions and lint baseline is green.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending",
    "notes": "Found in commit review on 2026-02-08 via `scripts/check_grafana_dashboards.py`."
  }
]
