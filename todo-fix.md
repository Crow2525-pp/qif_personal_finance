# Dashboard Fix Tasks

[
    {
        "id": 77,
        "title": "Eliminate recurring frontend console errors during dashboard navigation",
        "scope": "Grafana dashboard JSON field options/mappings across dashboards 02-16",
        "description": "Wide-screen traversal repeatedly logs client-side errors (invalid regex in build 322 and enum \"value\" mapping errors) which may hide real panel issues and degrade trust. Identify offending panel options/mappings and normalize to Grafana-supported values.",
        "category": "dashboard-fix",
        "effort": "medium",
        "status": "pending",
        "notes": "Observed 2026-02-07 during Playwright runs across wide resolutions."
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
        "scope": "grafana/provisioning/dashboards/03-monthly-budget-summary.json; scripts/check_grafana_dashboards.py",
        "description": "Dashboard 03 panel can validly return zero rows in some months, but smoke checks currently treat empty results as failure. Add checker allowlist semantics so valid empty states do not break gated CI.",
        "category": "dashboard-fix",
        "effort": "small",
        "status": "pending",
        "notes": "Panel SQL fallback fixed in #117; checker allowlist still needed."
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
        "scope": "grafana/provisioning/dashboards/*.json",
        "description": "Current checker reports 22 lint warnings (mostly markdown text overflow) in dashboards touched by recent commits. Reduce copy, resize panels, or split sections so guidance text is readable at wide resolutions and lint baseline is green.",
        "category": "dashboard-fix",
        "effort": "small",
        "status": "pending",
        "notes": "Found in commit review on 2026-02-08 via `scripts/check_grafana_dashboards.py`."
    }
],

## Timepicker Non-Responsive Panels (found 2026-02-12)

Dashboards with visible timepicker where stat/gauge/table panels ignore the selected time range.
Timeseries panels already use `$__timeFilter` and DO respond. The issue is summary panels
using hardcoded `CURRENT_DATE` or `LIMIT 1` instead of deriving the period from the time picker.

### Fix pattern
Replace `CURRENT_DATE` with `$__timeTo()::date` (or `$__timeTo()::timestamptz`) so panels
show data for the latest closed month WITHIN the selected range rather than always "today".

### Dashboard 02 - Cash Flow Analysis (20 panels, 0 stat/gauge respond)
| Panel ID | Title | Type | Priority | Status |
|----------|-------|------|----------|--------|
| 101 | Data Freshness | table | high | pending |
| 1 | Cash Flow Efficiency Score | gauge | high | pending |
| 2 | Cash Flow Status Rank | gauge | high | pending |
| 9 | Cash Flow Trend Score | gauge | high | pending |
| 3 | Latest Month Cash Flow | stat | high | pending |
| 6 | Cash Flow Metrics | stat | medium | pending |
| 7 | Year-to-Date Cash Flow | stat | medium | pending |
| 301 | MoM Changes | table | medium | pending |
| 200 | Outflow Breakdown | table | medium | pending |
| 201 | MoM Variance | table | medium | pending |
| 211 | Last 3 Months Net by Account | table | low | pending |
| 8 | Cash Flow Forecast | table | low | pending |
| 303 | Recurring Bills Forecast | table | low | pending |
| 302 | Recommendations | table | low | pending |
| 202 | Risk Alerts | table | low | pending |
| 903 | Data Quality Callouts | table | low | pending |
| 904 | Top Uncategorized Merchants | table | low | pending |

### Dashboard 05 - Savings Analysis (16 panels, 2 timeseries respond, 14 don't)
| Panel ID | Title | Type | Priority | Status |
|----------|-------|------|----------|--------|
| 101 | Data Freshness | table | high | pending |
| 1 | Savings Health Score | gauge | high | pending |
| 2 | Last Month Savings Rates | gauge | high | pending |
| 3 | Savings Performance Analysis | table | high | pending |
| 6 | Last Month Savings Breakdown | stat | medium | pending |
| 7 | Savings Rate Analysis | stat | medium | pending |
| 8 | Year-to-Date Progress | stat | medium | pending |
| 9 | Goal Tracking & Projections | stat | low | pending |
| 10 | Savings Recommendations | table | low | pending |
| 11 | Progress to 20% Goal | gauge | low | pending |
| 12 | Progress to FIRE Goal (25%) | gauge | low | pending |
| 13 | Current Benchmark Status | table | low | pending |
| 14 | Monthly Savings Required | table | low | pending |
| 15 | Action Priorities This Month | table | low | pending |

### Dashboard 11 - Account Performance (9 panels, 5 timeseries respond, 4 don't)
| Panel ID | Title | Type | Priority | Status |
|----------|-------|------|----------|--------|
| 9 | Data Freshness | table | high | pending |
| 2 | Last Month Account Balances | stat | high | pending |
| 8 | Account Summary (Latest Month) | table | medium | pending |

### Dashboard 01 - Executive Financial Overview (19 panels, 16 respond, 3 intentionally hardcoded)
Panels 1001 (Family Essentials), 1002 (Emergency Fund), 904 (Top 3 Actions) are intentionally
fixed to latest data — no fix needed.
