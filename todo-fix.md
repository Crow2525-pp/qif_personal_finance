# Dashboard Fix Tasks

[
  {
    "id": 9,
    "title": "Cash Flow Trends and Category panels readability is poor",
    "scope": "grafana/provisioning/dashboards/cash-flow-analysis-dashboard.json",
    "description": "Visual signal is weak at normal sizes; increase panel height or reduce series complexity.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "in_progress",
    "notes": "Partially addressed 2026-02-07 in `grafana/provisioning/dashboards/02-cash-flow-analysis.json`: improved trend labeling and readability; further visual-density tuning may still be needed at narrower widths."
  },
  {
    "id": 15,
    "title": "YTD Cash Flow appears identical to latest month values",
    "scope": "grafana/provisioning/dashboards/cash-flow-analysis-dashboard.json",
    "description": "YTD labels appear inconsistent with value behavior; verify query semantics.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "in_progress",
    "notes": "Partially addressed 2026-02-07 in `grafana/provisioning/dashboards/02-cash-flow-analysis.json`: added `YTD Months Included` indicator; underlying model semantics still need validation against source aggregates."
  },
  {
    "id": 17,
    "title": "Recommendation Drivers uses unclear category naming",
    "scope": "reporting models + cash flow dashboard",
    "description": "Category naming like Bank Transaction is not user-meaningful in recommendation context.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "in_progress",
    "notes": "Partially addressed 2026-02-07 in `grafana/provisioning/dashboards/02-cash-flow-analysis.json`: recommendation wording now uses clearer action/category framing; further model-level naming cleanup remains."
  },
  {
    "id": 23,
    "title": "Backfill or relabel stale Net Worth headline month",
    "scope": "grafana/provisioning/dashboards/04-household-net-worth-analysis.json",
    "description": "Net worth headline recency lags other dashboards; backfill data or clearly label staleness.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending",
    "notes": "Restored 2026-02-07 during backlog recovery."
  },
  {
    "id": 24,
    "priority": 6,
    "category": "dashboard-fix",
    "title": "Add cross-dashboard schema compatibility layer for renamed reporting columns",
    "description": "Multiple dashboards are breaking due to model/schema drift (`total_essential_expenses`, `uncategorized`, missing legacy relations). Introduce a compatibility layer (views or standardized aliases) to decouple dashboard SQL from frequent model renames.",
    "scope": "reporting schema compatibility views; dashboards 01/07/08",
    "effort": "medium",
    "status": "pending",
    "notes": "Pattern confirmed during Playwright run on 2026-02-07."
  },
  {
    "id": 25,
    "priority": 7,
    "category": "dashboard-fix",
    "title": "Add automated panel-level smoke test for priority dashboards 1-10",
    "description": "Current regressions reached production dashboards despite existing checks. Add CI/local smoke tests that fail on datasource 4xx/5xx or visible `No data` in dashboards 1-10, using Grafana API or Playwright MCP automation.",
    "scope": "scripts/check_grafana_dashboards.py; dashboard validation workflow",
    "effort": "medium",
    "status": "pending",
    "notes": "Playwright review on 2026-02-07 found multiple live failures not caught earlier."
  },
  {
    "id": 26,
    "priority": 8,
    "category": "dashboard-fix",
    "title": "Expose panel query/request IDs in TODO notes for faster triage",
    "description": "Triaging dashboard failures is slow without direct mapping between panel and failing request. Extend diagnostics to capture panel title + requestId + SQL error for each failed query so fixes can be assigned quickly.",
    "scope": "dashboard validation scripts and troubleshooting docs",
    "effort": "small",
    "status": "pending",
    "notes": "During Playwright review, failures were visible as `SQR***` ids but not mapped to panel names."
  },
  {
    "id": 40,
    "title": "Humanize reconciliation test names in Financial Reconciliation dashboard",
    "scope": "grafana/provisioning/dashboards/10-financial-reconciliation.json",
    "description": "Raw test identifiers are difficult for monthly review; map to user-facing labels and action text.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending",
    "notes": "Restored 2026-02-07 during backlog recovery."
  },
  {
    "id": 56,
    "category": "dashboard-fix",
    "title": "Extend automated smoke tests to dashboards 11-23",
    "description": "Recent review found live query failures in non-core dashboards that were not pre-caught. Extend dashboard validation to include 11-23 and fail on datasource 4xx/5xx, unresolved variables, or visible `No data` in required panels.",
    "scope": "scripts/check_grafana_dashboards.py; Playwright/Grafana API validation workflow",
    "effort": "medium",
    "status": "pending",
    "notes": "Observed issues on dashboards 11, 15, and 17 during 2026-02-07 run."
  },
  {
    "id": 59,
    "title": "Finish Amazon schema migration beyond table rename",
    "scope": "grafana/provisioning/dashboards/17-amazon-spending-analysis.json",
    "description": "Dashboard 17 still has residual legacy field/join assumptions despite table rename.",
    "category": "dashboard-fix",
    "effort": "medium",
    "status": "pending",
    "notes": "Restored 2026-02-07 during backlog recovery."
  },
  {
    "id": 60,
    "title": "Ensure reporting compat views are materialized in active environment",
    "scope": "pipeline_personal_finance/dbt_finance/models/reporting/compat/*",
    "description": "Compatibility relations referenced by historical SQL are absent in runtime schema.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending",
    "notes": "Restored 2026-02-07 during backlog recovery."
  },
  {
    "id": 61,
    "category": "dashboard-fix",
    "title": "Add pre-merge dashboard SQL schema validation (table+column existence)",
    "description": "Recent commit-level fixes changed table references but missed column/join-key migrations, causing runtime regressions. Add automated validation that parses dashboard SQL and checks referenced tables/columns against `information_schema` before merge.",
    "scope": "scripts/check_grafana_dashboards.py; CI workflow",
    "effort": "medium",
    "status": "pending",
    "notes": "Regression pattern identified while reviewing commit `e63eb93`."
  },
  {
    "id": 62,
    "category": "dashboard-fix",
    "title": "Add checklist for dashboard query migrations to prevent partial fixes",
    "description": "When migrating a dashboard query source, require a checklist: table rename, column mapping, join-key validation, unit tests, and live panel verification. This prevents partial migrations that pass review but fail in Grafana.",
    "scope": "contribution docs + PR template for dashboard changes",
    "effort": "tiny",
    "status": "pending",
    "notes": "Process gap observed in commit review on 2026-02-07."
  },
  {
    "status": "pending",
    "notes": "Verified 2026-02-07 (2560x1307 and 3440x1440): /api/ds/query SQR118, error pq: column \"transaction_count\" does not exist.",
    "scope": "grafana/provisioning/dashboards/02-cash-flow-analysis.json; panel id 904",
    "category": "dashboard-fix",
    "effort": "tiny",
    "id": 67,
    "title": "Fix Cash Flow Analysis Top Uncategorized Merchants schema mismatch",
    "description": "Dashboard 02 panel 904 still references transaction_count in reporting.viz_uncategorized_transactions_with_original_memo, causing datasource failures and No data at wide resolutions."
  },
  {
    "status": "pending",
    "notes": "Verified 2026-02-07 (2560x1307 and 3440x1440): /api/ds/query SQR113, error pq: column \"transaction_count\" does not exist.",
    "scope": "grafana/provisioning/dashboards/08-outflows-insights.json; panel id 906",
    "category": "dashboard-fix",
    "effort": "tiny",
    "id": 68,
    "title": "Fix Outflows Insights Top Uncategorized Merchants schema mismatch",
    "description": "Dashboard 08 panel 906 aggregates SUM(transaction_count), but active view exposes txn_count. Query fails and leaves panel empty."
  },
  {
    "status": "pending",
    "notes": "Observed 2026-02-07 via Playwright markdown overflow + checker lint (len 546 allowed~5).",
    "scope": "grafana/provisioning/dashboards/02-cash-flow-analysis.json; panel id 100",
    "category": "dashboard-fix",
    "effort": "small",
    "id": 69,
    "title": "Reduce Dashboard Instructions overflow in Cash Flow Analysis at wide screens",
    "description": "At 2560x1307 and 3440x1440, instructions text still overflows its panel height and truncates content. Split content or increase panel height."
  },
  {
    "status": "pending",
    "notes": "Observed 2026-02-07 via checker lint (len 675 allowed~8) and wide-screen pass.",
    "scope": "grafana/provisioning/dashboards/08-outflows-insights.json; panel id 100",
    "category": "dashboard-fix",
    "effort": "small",
    "id": 70,
    "title": "Reduce Dashboard Instructions overflow in Outflows Insights at wide screens",
    "description": "Instructions markdown overflows and is hard to scan even on ultrawide. Reformat to concise bullets and/or expand panel height."
  },
  {
    "status": "pending",
    "notes": "Observed 2026-02-07 at 2560x1307 and 3440x1440 (markdown overflow sample captured).",
    "scope": "grafana/provisioning/dashboards/04-household-net-worth-analysis.json; instructions markdown panel",
    "category": "dashboard-fix",
    "effort": "small",
    "id": 71,
    "title": "Shrink Household Net Worth instruction block to fit wide-layout panel",
    "description": "Dashboard 04 instruction markdown overflows panel height at wide resolutions, forcing hidden guidance text."
  },
  {
    "status": "pending",
    "notes": "Observed 2026-02-07 at 2560x1307 and 3440x1440 (markdown overflow sample captured).",
    "scope": "grafana/provisioning/dashboards/05-savings-analysis.json; instructions markdown panel",
    "category": "dashboard-fix",
    "effort": "small",
    "id": 72,
    "title": "Shrink Savings Analysis instruction block to fit wide-layout panel",
    "description": "Dashboard 05 instruction markdown overflows panel height at wide resolutions, reducing readability for first-time users."
  },
  {
    "status": "pending",
    "notes": "Observed 2026-02-07 via Playwright markdown overflow and checker lint.",
    "scope": "grafana/provisioning/dashboards/09-transaction-analysis.json; instructions markdown panel",
    "category": "dashboard-fix",
    "effort": "small",
    "id": 73,
    "title": "Reduce Transaction Analysis instruction panel overflow on wide screens",
    "description": "Dashboard 09 instructions still overflow despite large viewport. Shorten copy or increase panel height to avoid clipped guidance."
  },
  {
    "status": "pending",
    "notes": "Observed 2026-02-07 via Playwright markdown overflow and checker lint warnings.",
    "scope": "grafana/provisioning/dashboards/10-financial-reconciliation.json; section text panels ids 300/302/304",
    "category": "dashboard-fix",
    "effort": "small",
    "id": 74,
    "title": "Fix overflow in Financial Reconciliation section intro text panels",
    "description": "Dashboard 10 section text panels (Actionable Fix List, Data Quality Blockers, Check Details) overflow their 2-row containers on wide screens, reducing discoverability."
  },
  {
    "status": "pending",
    "notes": "Observed 2026-02-07 at 2560x1307 and 3440x1440 (markdown overflow sample captured).",
    "scope": "grafana/provisioning/dashboards/12-financial-projections.json; panel id 8",
    "category": "dashboard-fix",
    "effort": "small",
    "id": 75,
    "title": "Refactor Scenario Assumptions panel to avoid overflow in Financial Projections",
    "description": "Dashboard 12 Scenario Assumptions block overflows the panel on wide screens, burying assumptions users need for interpretation."
  },
  {
    "status": "pending",
    "notes": "Observed 2026-02-07 at 2560x1307 and 3440x1440 (markdown overflow sample captured).",
    "scope": "grafana/provisioning/dashboards/15-mortgage-payoff.json; guide markdown panel",
    "category": "dashboard-fix",
    "effort": "tiny",
    "id": 76,
    "title": "Tighten Mortgage Payoff guide text for wide-layout readability",
    "description": "Dashboard 15 guide markdown overflows available panel height even at wide resolutions; reduce copy and move details to secondary panel."
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
    "status": "pending",
    "notes": "Migrated from todo.md commit review faults (2026-02-07)."
  },
  {
    "id": 79,
    "title": "Require commit-level dashboard verification evidence",
    "scope": "PR template and dashboard validation workflow",
    "description": "For any multi-dashboard JSON edit, require before/after panel failure counts and query error summary attached to commit or PR.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending",
    "notes": "Migrated from todo.md commit review faults (2026-02-07)."
  },
  {
    "id": 80,
    "title": "Fix Account Performance runtime SQL macro errors",
    "scope": "grafana/provisioning/dashboards/11-account-performance.json",
    "description": "Panels 1, 3, 4, 5, and 7 fail due to boolean/type macro misuse (period_date/year_month expressions). Correct WHERE clauses and validate each panel renders.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending",
    "notes": "Migrated from todo.md wide-screen audit batch 1 (dashboard 11)."
  },
  {
    "id": 81,
    "title": "Normalize Account Performance UX semantics and currency",
    "scope": "grafana/provisioning/dashboards/11-account-performance.json",
    "description": "Replace technical panel names, switch units to AUD, and add explicit scope labels for latest-month vs history panels.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending"
  },
  {
    "id": 82,
    "title": "Harden Account Performance null/stale behaviors",
    "scope": "grafana/provisioning/dashboards/11-account-performance.json",
    "description": "Add no-row fallbacks for last-month panels, stale-data warnings, and timezone/cadence metadata in Data Freshness.",
    "category": "dashboard-fix",
    "effort": "small",
    "status": "pending"
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
  }
]

