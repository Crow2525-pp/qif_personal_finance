# Completed Tasks

This file contains tasks moved from plan.md once their status became done.

## Done Items

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
    "title": "Restore Mortgage Payoff dashboard source-model contract",
    "description": "Dashboard 15 currently references `reporting.viz_mortgage_payoff_summary`, `reporting.viz_mortgage_payoff_monthly`, and `reporting.viz_mortgage_payoff_sensitivity`, but these relations are not materialized in the dbt project. Rebuild the missing mortgage reporting models (or retarget the dashboard to canonical existing models), add dbt tests on required columns, and verify every panel in 15-mortgage-payoff renders without relation-not-found errors.",
    "scope": "grafana/provisioning/dashboards/15-mortgage-payoff.json; pipeline_personal_finance/dbt_finance/models/reporting/mortgage/*.sql; pipeline_personal_finance/dbt_finance/models/reporting/schema.yml",
    "effort": "medium",
    "status": "done",
    "notes": "Cross-dashboard SQL-to-model audit on 2026-02-21 found this as the only dashboard with unresolved model references. Completed by another LLM on 2026-02-21."
  },
  {
    "id": 47,
    "category": "dashboard-fix",
    "title": "Make timepicker semantics truthful across all dashboards",
    "description": "Every dashboard exposes a visible timepicker, but many summary panels still compute off `CURRENT_DATE` and `LIMIT 1`, producing results that ignore selected windows. Replace hardcoded latest-month logic with selected-window CTEs anchored to `$__timeTo()`/`$__timeFilter`, explicitly mark intentional fixed-latest panels in panel subtitles, and add automated checks that detect non-responsive time windows.",
    "scope": "grafana/provisioning/dashboards/*.json; scripts/check_grafana_dashboards.py",
    "effort": "medium",
    "status": "done",
    "notes": "2026-02-21 audit counts: 281 SQL targets, 99 with CURRENT_DATE, 65 with LIMIT 1. Completed by another LLM on 2026-02-21."
  },
  {
    "id": 48,
    "category": "dashboard-fix",
    "title": "Standardize display units and sign conventions across the dashboard suite",
    "description": "Desktop and mobile dashboards currently mix `currencyUSD`, `currencyAUD`, `prefix:$`, and inconsistent `percent`/`percentunit` semantics, with some liability metrics showing opposite sign behavior between cards and tables. Define one suite-wide unit/sign contract, migrate all affected field configs and SQL aliases, and enforce via lint so new dashboards cannot drift.",
    "scope": "grafana/provisioning/dashboards/*.json; grafana/provisioning/dashboards/README.md; representative fixes in 15-mortgage-payoff.json, 21-savings-performance-mobile.json, 22-assets-networth-mobile.json",
    "effort": "medium",
    "status": "done",
    "notes": "Completed by another LLM on 2026-02-21."
  },
  {
    "id": 49,
    "category": "dashboard-fix",
    "title": "Harden dashboard validation tooling for CI-grade signal",
    "description": "Current validation output is noisy for triage: panel traversal can over-report failures, macro handling is partial for local SQL checks, and outputs are not structured for PR evidence. Refactor validators to produce deterministic panel-level results (no duplicate counting), consistent macro substitution by datasource mode, and machine-readable artifacts consumable by CI and review bots.",
    "scope": "pipeline_personal_finance/dbt_finance/scripts/validate_grafana_dashboards.py; scripts/check_grafana_dashboards.py; scripts/README.md",
    "effort": "medium",
    "status": "done",
    "notes": "Observed while running full-suite validation on 2026-02-21. Completed by another LLM on 2026-02-21."
  },
  {
    "id": 50,
    "category": "dashboard-fix",
    "title": "Close Postgres-vs-DuckDB SQL drift in local dashboard verification",
    "description": "The local workflow supports DuckDB rendering, but many dashboard SQL targets are Postgres-specific, causing false-negative local reviews and reducing trust before merge. Introduce an explicit compatibility strategy (compat views, translated SQL layer, or dual dashboard targets), document one sanctioned local verification path, and wire validators to the chosen approach.",
    "scope": "grafana/provisioning/dashboards/*.json; grafana/provisioning_local/datasources/duckdb.yml; pipeline_personal_finance/dbt_finance/LOCAL_DEV.md; scripts/check_grafana_dashboards.py",
    "effort": "medium",
    "status": "done",
    "notes": "Completed by another LLM on 2026-02-21."
  },
  {
    "id": 51,
    "category": "dashboard-feature",
    "title": "Create a Financial Review Command Center dashboard",
    "description": "Add a top-level dashboard that orchestrates the monthly review sequence (Executive -> Cash/Budget -> Net Worth -> Savings -> Reconciliation -> Projections), surfaces data-quality blockers before interpretation, and provides one-click deep links into the domain dashboards with preserved context. This becomes the canonical entry point for monthly/quarterly review.",
    "scope": "new grafana/provisioning/dashboards/00-financial-review-command-center.json; deep-link integration with dashboards 01-23",
    "effort": "medium",
    "status": "done",
    "notes": "Completed by another LLM on 2026-02-21."
  },
  {
    "id": 52,
    "category": "dashboard-feature",
    "title": "Implement shared global filter context across dashboard families",
    "description": "Add common template variables (for example `review_month`, `account_group`, `category_group`, `scenario`) and carry them through inter-dashboard links so users do not lose analytical context when moving from overview to drilldown. Include defaults and guardrails so mobile and desktop dashboards stay aligned.",
    "scope": "grafana/provisioning/dashboards/01-23; shared templating conventions in grafana/provisioning/dashboards/README.md",
    "effort": "medium",
    "status": "done",
    "notes": "2026-02-21 audit found no templating variables across provisioned dashboards, forcing context resets between screens. Completed by another LLM on 2026-02-21."
  },
  {
    "id": 53,
    "category": "dashboard-feature",
    "title": "Establish mandatory drillthrough and breadcrumb UX standards",
    "description": "Define for each dashboard: where users should go next for root cause, and how they return without losing context. Implement standard data links, breadcrumbs, and back-links on all major KPI and anomaly panels so dashboard navigation becomes a deterministic investigation workflow instead of ad-hoc tab hopping.",
    "scope": "grafana/provisioning/dashboards/*.json; grafana/provisioning/dashboards/README.md interaction conventions",
    "effort": "medium",
    "status": "done",
    "notes": "Audit evidence: only a small subset of dashboards currently contains data links; most panels are dead ends. Completed by another LLM on 2026-02-21."
  },
  {
    "id": 54,
    "category": "dashboard-feature",
    "title": "Add KPI metric dictionary and formula lineage layer",
    "description": "Create a shared metric-definition model documenting formula, grain, freshness expectation, and source table lineage for each headline KPI. Expose this via linked 'How calculated' panels so users can validate meaning and trust before acting on metric changes.",
    "scope": "new reporting metric-definition model(s); dashboard help/link panels in 01, 10, 18, 23 with references from other dashboards",
    "effort": "medium",
    "status": "done",
    "notes": "Completed by another LLM on 2026-02-21."
  },
  {
    "id": 55,
    "category": "dashboard-feature",
    "title": "Create desktop-mobile KPI parity contract with automated checks",
    "description": "Materialize canonical KPI views consumed by both desktop and mobile dashboards so values, thresholds, and labels cannot diverge by form factor. Add parity tests that fail CI when core KPIs disagree between desktop and mobile representations for the same period.",
    "scope": "shared reporting KPI models; grafana/provisioning/dashboards/01-23 query alignment; dbt tests/CI checks for parity",
    "effort": "medium",
    "status": "done",
    "notes": "Completed by another LLM on 2026-02-21."
  },
  {
    "id": 56,
    "category": "dashboard-feature",
    "title": "Add recommendation outcome tracking to close the action loop",
    "description": "Track whether dashboard recommendations were acted on and measure subsequent financial impact (for example uncategorized reduction, expense delta, savings-rate lift). Surface these outcomes in executive and operations dashboards so recommendations become accountable interventions rather than static advice.",
    "scope": "new recommendation_outcomes model(s); panels in executive, cash-flow, budget, outflows, and transaction dashboards",
    "effort": "medium",
    "status": "done",
    "notes": "Completed by another LLM on 2026-02-21."
  }
]

