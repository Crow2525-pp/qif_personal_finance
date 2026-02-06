# Dashboard Fixes Plan

[
  {
    "id": 1,
    "category": "dashboard-fix",
    "title": "Fix Executive dashboard queries failing with syntax error near ')'",
    "description": "API check shows many Executive dashboard panels failing with SQL syntax errors where time macros render as empty parentheses (e.g., ()::timestamptz). Ensure Grafana macros/time variables are correctly substituted so queries execute without errors.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; time macro usage in panel SQL",
    "effort": "medium",
    "status": "pending",
    "notes": "Observed via scripts/check_grafana_dashboards.py on 2026-02-06 for dashboard UID executive_dashboard."
  },
  {
    "id": 2,
    "category": "dashboard-fix",
    "title": "Restore Data Freshness panel query",
    "description": "Data Freshness panel fails during API check. Validate the reporting.rpt_executive_dashboard source and the panel query so it returns a last refresh timestamp for the selected month.",
    "scope": "reporting.rpt_executive_dashboard; grafana/provisioning/dashboards/executive-dashboard.json",
    "effort": "small",
    "status": "done",
    "notes": "Panel id 101 in Executive Financial Overview dashboard. - FIXED by datasource change to point to production DB (2026-02-06)."
  },
  {
    "id": 3,
    "category": "dashboard-fix",
    "title": "Restore Top Uncategorized Merchants panel query",
    "description": "Top Uncategorized Merchants panel fails during API check. Ensure reporting.viz_uncategorized_transactions_with_original_memo (or replacement) returns rows for the current window and the panel query runs without errors.",
    "scope": "reporting.viz_uncategorized_transactions_with_original_memo; grafana/provisioning/dashboards/executive-dashboard.json",
    "effort": "small",
    "status": "done",
    "notes": "Panel id 902 in Executive Financial Overview dashboard. - FIXED by datasource change to point to production DB (2026-02-06)."
  },
  {
    "id": 4,
    "category": "dashboard-fix",
    "title": "Repair Data Quality Callouts query",
    "description": "Data Quality Callouts panel fails during API check. Validate the period window logic and ensure query executes and returns values for stale accounts, unmatched transfers, and uncategorized spend.",
    "scope": "reporting.rpt_outflows_insights_dashboard; grafana/provisioning/dashboards/executive-dashboard.json",
    "effort": "small",
    "status": "done",
    "notes": "Panel id 901 in Executive Financial Overview dashboard. - FIXED by datasource change to point to production DB (2026-02-06)."
  },
  {
    "id": 5,
    "category": "dashboard-fix",
    "title": "Fix text panel overflow in 'How to Read This Dashboard'",
    "description": "Layout lint flags the How-to-read text panel as likely overflowing its grid height. Reduce content length, increase panel height, or split into multiple text panels.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json",
    "effort": "tiny",
    "status": "pending",
    "notes": "Lint warning: panel id 100 on Executive Financial Overview dashboard."
  },
  {
    "id": 6,
    "category": "dashboard-fix",
    "title": "Health & Risk KPIs table shows missing Delta Ratio for 'Accounts At Risk'",
    "description": "On the Executive Financial Overview dashboard, the 'Accounts At Risk' row renders an empty Delta Ratio cell while the column exists for other rows. Ensure the query returns a value for this field (or hide the column when not applicable) to avoid a blank cell.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Health & Risk KPIs panel query",
    "effort": "tiny",
    "status": "done",
    "notes": "FIXED (2026-02-06): Updated SQL query to return 0 for 0/0 case instead of NULL. Delta Ratio now displays '0%' instead of blank cell."
  },
  {
    "id": 7,
    "category": "dashboard-fix",
    "title": "AI Financial Insights column shows navigation link instead of accounts count",
    "description": "The 'Accounts Needing Attention' column renders a 'View Full Executive Dashboard' link instead of a numeric count or account list. Update the panel query/field mapping so this column reflects actual accounts needing attention (or rename the column if it is intended to be a link).",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; AI Financial Insights panel query",
    "effort": "small",
    "status": "done",
    "notes": "FIXED (2026-02-06): Updated SQL query to use NULLIF to handle empty string in accounts_with_issues column. Now displays 'None flagged' instead of empty cell."
  }
]
