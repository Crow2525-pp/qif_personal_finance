# Dashboard Fixes Plan

[
  {
    "id": 13,
    "category": "dashboard-fix",
    "title": "Small-screen KPI labels truncate (Savings Performance, Expense Ratio)",
    "description": "At 375x812, KPI label text truncates (e.g., 'Savings Performance', 'Expense Ratio (%)'), which suggests the stat tiles are not responsive to mobile widths. Consider stacking or wrapping KPI labels on narrow viewports.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; KPI tiles",
    "effort": "tiny",
    "status": "pending",
    "notes": "VERIFIED (2026-02-06): KPI labels truncate at 375x812 but values remain visible. Accepted - mobile viewing not primary use case. - REQUIRES FIX: User confirmed these issues need to be addressed for proper dashboard functionality."
  },
  {
    "id": 15,
    "category": "dashboard-fix",
    "title": "Clarify time basis for 'Current'/'Previous'/'Delta' columns",
    "description": "Tables such as Key Executive KPIs, Health & Risk KPIs, and Month-over-Month Rate Changes use 'Current' and 'Previous' without stating the period. Make the columns explicit (e.g., 'Current Month', 'Previous Month') or add a description that defines the comparison window.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; KPI tables",
    "effort": "small",
    "status": "pending",
    "notes": "Usability review on 2026-02-06: ambiguous time basis for comparisons."
  },
  {
    "id": 22,
    "category": "dashboard-fix",
    "title": "Ultrawide text panels exceed readable line length",
    "description": "How to Read and Executive Summary span nearly full width on 2560x1307, producing extremely long lines that reduce readability. Add a max-width or use multi-column text to keep line lengths reasonable.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; How to Read, Executive Summary panels",
    "effort": "small",
    "status": "pending",
    "notes": "Observed on 2560x1307: text spans ~2513px."
  },
  {
    "id": 23,
    "category": "dashboard-fix",
    "title": "Full-width tables feel too stretched on ultrawide screens",
    "description": "AI Financial Insights and Status Highlights stretch across the full 2560px width, making scanning rows harder. Consider constraining max width or splitting into two columns on ultrawide layouts.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; AI Financial Insights, Status Highlights panels",
    "effort": "small",
    "status": "pending",
    "notes": "Observed on 2560x1307: tables span ~2513px."
  },
  {
    "id": 24,
    "category": "dashboard-fix",
    "title": "Data Freshness table is overkill for a single-row KPI",
    "description": "Data Freshness currently uses a table for a single row. Consider converting to KPI tiles (Data Through, Last Refresh) or a compact stat panel to make the freshness message more immediate.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Data Freshness panel",
    "effort": "small",
    "status": "pending",
    "notes": "Usability review on 2026-02-06: table format feels heavier than necessary."
  },
  {
    "id": 25,
    "category": "dashboard-fix",
    "title": "Family Essentials shows a single total without context",
    "description": "Family Essentials (Last Month) is a single number with no trend or category breakdown, making it hard to interpret. Consider a small trend sparkline or a category breakdown to explain what drives the total.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Family Essentials panel",
    "effort": "small",
    "status": "pending",
    "notes": "Usability review on 2026-02-06: value lacks explanatory context."
  },
  {
    "id": 26,
    "category": "dashboard-fix",
    "title": "KPI tables should be more glanceable than dense tables",
    "description": "Key Executive KPIs and Health & Risk KPIs are short tables with a few rows, which makes scanning slower than necessary. Consider KPI tiles with trend indicators or small sparklines to improve readability and prioritization.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Key Executive KPIs, Health & Risk KPIs panels",
    "effort": "small",
    "status": "pending",
    "notes": "Usability review on 2026-02-06: tables feel heavy for the amount of data shown."
  },
  {
    "id": 27,
    "category": "dashboard-fix",
    "title": "Month-over-Month Rate Changes better suited to bar chart",
    "description": "Month-over-Month Rate Changes is a two-row table of deltas; a horizontal bar chart with positive/negative coloring would communicate direction and magnitude faster than the table.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Month-over-Month Rate Changes panel",
    "effort": "small",
    "status": "pending",
    "notes": "Usability review on 2026-02-06: table hides directionality at a glance."
  }
]
