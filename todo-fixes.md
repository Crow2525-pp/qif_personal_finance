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
    "id": 5,
    "category": "dashboard-fix",
    "title": "Fix text panel overflow in 'How to Read This Dashboard'",
    "description": "Layout lint flags the How-to-read text panel as likely overflowing its grid height. Reduce content length, increase panel height, or split into multiple text panels.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json",
    "effort": "tiny",
    "status": "pending",
    "notes": "Lint warning: panel id 100 on Executive Financial Overview dashboard."
  }
]
