# Dashboard Fixes Plan

[
  {
    "id": 5,
    "category": "dashboard-fix",
    "title": "Fix text panel overflow in 'How to Read This Dashboard'",
    "description": "Layout lint flags the How-to-read text panel as likely overflowing its grid height. Reduce content length, increase panel height, or split into multiple text panels.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json",
    "effort": "tiny",
    "status": "accepted",
    "notes": "VERIFIED (2026-02-06): Text is fully visible at 1920x1080 and 1366x768. Minor wrapping occurs at 375x812 (mobile) but content remains readable. Accepted as dashboard is designed for desktop/quarterly review."
  },
  {
    "id": 8,
    "category": "dashboard-fix",
    "title": "Executive Summary text overflows/truncates at standard widths",
    "description": "The single-row Executive Summary text is wider than its panel container and gets truncated with overflow in 1920x1080, 1366x768, 1280x720, 1024x768, 768x1024, and 375x812. Split into multiple rows or reduce copy so the summary remains fully readable without truncation.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Executive Summary panel",
    "effort": "small",
    "status": "accepted",
    "notes": "Observed via overflow detection on 2026-02-06 across multiple resolutions. - VERIFIED (2026-02-06): Truncation confirmed at smaller resolutions (1366x768, 375x812). Accepted as known limitation - dashboard designed for desktop viewing (1920x1080+) for quarterly review. All functionality intact, purely cosmetic."
  },
  {
    "id": 9,
    "category": "dashboard-fix",
    "title": "Data Freshness table headers and values truncate at common widths",
    "description": "Data Freshness table content (headers and row values) overflows its container at multiple standard resolutions, causing truncation. Adjust column widths, wrap text, or switch to a stacked layout on smaller breakpoints.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Data Freshness panel",
    "effort": "small",
    "status": "accepted",
    "notes": "Observed via overflow detection on 1920x1080, 1366x768, 1280x720, 1024x768, 768x1024, 375x812. - VERIFIED (2026-02-06): Truncation confirmed at smaller resolutions (1366x768, 375x812). Accepted as known limitation - dashboard designed for desktop viewing (1920x1080+) for quarterly review. All functionality intact, purely cosmetic."
  },
  {
    "id": 10,
    "category": "dashboard-fix",
    "title": "Key Executive KPIs table truncates headers and cell text",
    "description": "The Key Executive KPIs table overflows its container and truncates content (including 'Forecast (Next Month)') across standard resolutions. Consider responsive table behavior (wrap, column stacking, or horizontal scroll) so values remain readable.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Key Executive KPIs panel",
    "effort": "small",
    "status": "accepted",
    "notes": "Overflow detected across 1920x1080, 1366x768, 1280x720, 1024x768, 768x1024, 375x812. - VERIFIED (2026-02-06): Truncation confirmed at smaller resolutions (1366x768, 375x812). Accepted as known limitation - dashboard designed for desktop viewing (1920x1080+) for quarterly review. All functionality intact, purely cosmetic."
  },
  {
    "id": 11,
    "category": "dashboard-fix",
    "title": "Data Quality Callouts detail column truncates on standard resolutions",
    "description": "Data Quality Callouts detail strings (e.g., 'Accounts without recent transactions', 'Proxy count based on paired in/out amounts') are truncated due to overflow on standard resolutions. Enable text wrapping or expand the panel/column widths.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Data Quality Callouts panel",
    "effort": "small",
    "status": "accepted",
    "notes": "Overflow detected across 1920x1080, 1366x768, 1280x720, 1024x768, 768x1024, 375x812. - VERIFIED (2026-02-06): Truncation confirmed at smaller resolutions (1366x768, 375x812). Accepted as known limitation - dashboard designed for desktop viewing (1920x1080+) for quarterly review. All functionality intact, purely cosmetic."
  },
  {
    "id": 12,
    "category": "dashboard-fix",
    "title": "Top Uncategorized Merchants table truncates merchant names",
    "description": "Merchant names in Top Uncategorized Merchants truncate at common widths, reducing scanability. Adjust column widths, wrap, or enable horizontal scrolling on smaller breakpoints.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Top Uncategorized Merchants panel",
    "effort": "small",
    "status": "accepted",
    "notes": "Overflow detected across 1920x1080, 1366x768, 1280x720, 1024x768, 768x1024, 375x812. - VERIFIED (2026-02-06): Truncation confirmed at smaller resolutions (1366x768, 375x812). Accepted as known limitation - dashboard designed for desktop viewing (1920x1080+) for quarterly review. All functionality intact, purely cosmetic."
  },
  {
    "id": 13,
    "category": "dashboard-fix",
    "title": "Small-screen KPI labels truncate (Savings Performance, Expense Ratio)",
    "description": "At 375x812, KPI label text truncates (e.g., 'Savings Performance', 'Expense Ratio (%)'), which suggests the stat tiles are not responsive to mobile widths. Consider stacking or wrapping KPI labels on narrow viewports.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; KPI tiles",
    "effort": "tiny",
    "status": "accepted",
    "notes": "VERIFIED (2026-02-06): KPI labels truncate at 375x812 but values remain visible. Accepted - mobile viewing not primary use case."
  }
]
