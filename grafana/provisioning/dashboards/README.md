# Grafana Dashboards Provisioning

This folder is mounted into Grafana so dashboards auto-load from versioned JSON, not from manual UI exports.

- **Prod compose** mounts `./grafana/provisioning` to `/etc/grafana/provisioning` (see `docker-compose.yml`).
- **Local compose** mounts `./grafana/provisioning/dashboards` and `./grafana/provisioning_local/datasources` (see `docker-compose.local.yml`).
- Grafana provider (`dashboards.yml`) scans all `*.json` here every ~10 seconds; placing a file makes it available without additional config.

## Workflow
1) Edit JSON in this directory (keep UIDs stable so Grafana overwrites the same dashboards).
2) For quick sync without restarting Grafana, run `python scripts/push_grafana_dashboards.py` (uses Grafana API and defaults to all JSON files).
3) Verify panels with the pre-commit dashboard checklist in `CLAUDE.md`.
4) Use the Playwright MCP server to validate dashboards quickly:
   - `mcp__playwright__browser_navigate(url="http://localhost:3001")`
   - log in (credentials from your `.env`)
   - `mcp__playwright__browser_take_screenshot(filename="screenshots/dashboard-review.png", fullPage=true)`
   - look for “No data”, datasource errors, or console errors; attach the screenshot to `activity.md` for the task.

## Conventions
- Currency must render as USD ($); avoid AUD labels in panel formatting.
- Percent data: ratio fields → `percentunit`, percentage fields (0–100) → `percent`; name ratio fields without `_pct`, add `_pct` suffix for 0–100 values.
- Pie/bar/stat panels should display actual values (`displayLabels: ["name","value"]`, `reduceOptions.values: true`).
- Mobile dashboards are prefixed `01-..` to `06-..`; keep numbering contiguous when adding new mobile layouts.

## Adding dashboards
- Save the exported JSON directly here; no extra registration is needed because the provider watches the directory.
- Ensure filenames are descriptive; keep `uid` unique and stable to avoid clobbering unrelated dashboards.
- If a dashboard should not be provisioned, keep it outside this folder or rename with a non-`.json` extension.

## Drillthrough Navigation Standards

Every key dashboard exposes a `links` array in its JSON root. These links render in the Grafana toolbar
(the external-link icon next to the star) and let users jump to related dashboards while preserving the
current time range (`keepTime: true`).

### Navigation hierarchy

| From | Links to |
|------|----------|
| 01 - Executive Financial Overview | 02 Cash Flow, 05 Savings, 06 Category Spending, 09 Transaction Analysis, 10 Reconciliation |
| 02 - Cash Flow Analysis | 01 Executive, 06 Category Spending, 09 Transaction Analysis |
| 05 - Savings Analysis | 01 Executive, 04 Net Worth, 06 Category Spending |
| 06 - Category Spending Analysis | 09 Transaction Analysis |
| 09 - Transaction Analysis | 01 Executive, 06 Category Spending, 08 Outflows Insights |
| 10 - Financial Reconciliation | 09 Transaction Analysis |

### Link object schema

Add entries to the top-level `"links"` array of the dashboard JSON:

```json
{
  "title": "View in 02 - Cash Flow Analysis",
  "url": "/d/cash_flow_analysis",
  "type": "link",
  "keepTime": true,
  "includeVars": false,
  "icon": "external link",
  "targetBlank": false
}
```

- `keepTime: true` — destination dashboard inherits the current global time range.
- `includeVars: false` — template variables are not forwarded (each dashboard manages its own).
- `targetBlank: false` — links open in the same tab to support back-navigation via the browser.

### Adding new dashboards

When adding a dashboard that fits the review workflow:
1. Decide which existing dashboards should link to it and which it should link back to.
2. Update the `links` array in both the new and existing dashboard JSON files.
3. Push changes via `scripts/push_grafana_dashboards.py` or the API (`POST /api/dashboards/db` with `overwrite: true`).
4. Update the navigation hierarchy table above.
