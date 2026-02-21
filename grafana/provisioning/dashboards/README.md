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

## Cross-Dashboard Navigation Links

### Time-range context preservation

All cross-dashboard links must propagate the current time range to the destination dashboard using Grafana's built-in `${__url_time_range}` variable. This resolves to `from=<epoch_ms>&to=<epoch_ms>` at render time.

**URL pattern for links with no existing query params:**
```
/d/<uid>?orgId=1&${__url_time_range}
```

**URL pattern for links that also pass template variables:**
```
/d/<uid>?orgId=1&${__url_time_range}&var-time_window=${time_window}&var-dashboard_period=${dashboard_period}
```

### Standard template variables

Dashboards in the main analysis family share the following template variables so that context passes correctly through navigation links:

| Variable | Type | Values | Purpose |
|---|---|---|---|
| `time_window` | custom | `latest_month`, `ytd`, `trailing_12m` | Controls the SQL aggregation window in panel queries |
| `dashboard_period` | query (postgres) | `Latest`, `YYYY-MM` list | Selects a specific closed month for point-in-time views |

**Adding `time_window` to a dashboard:**
```json
{
  "name": "time_window",
  "label": "Time Window",
  "type": "custom",
  "hide": 0,
  "current": {"text": "Latest Month", "value": "latest_month", "selected": true},
  "options": [
    {"text": "Latest Month", "value": "latest_month", "selected": true},
    {"text": "Year to Date", "value": "ytd", "selected": false},
    {"text": "Trailing 12 Months", "value": "trailing_12m", "selected": false}
  ],
  "query": "latest_month,ytd,trailing_12m",
  "includeAll": false,
  "multi": false,
  "skipUrlSync": false
}
```

### Dashboards with cross-dashboard links

| Source dashboard | Destination dashboard | Variables passed |
|---|---|---|
| `executive-dashboard` | `cash_flow_analysis`, `savings_analysis`, `category-spending-v2`, `transaction_analysis_dashboard`, `outflows_reconciliation` | `${__url_time_range}`, `time_window` |
| `cash-flow-analysis-dashboard` | `executive_dashboard`, `category-spending-v2`, `transaction_analysis_dashboard`, `outflows_reconciliation` | `${__url_time_range}`, `time_window` |
| `savings-analysis-dashboard` | `executive_dashboard`, `household_net_worth`, `category-spending-v2` | `${__url_time_range}`, `time_window` |
| `outflows-reconciliation-dashboard` | `executive_dashboard`, `transaction_analysis_dashboard` | `${__url_time_range}`, `time_window` |
| `outflows-insights-dashboard` | `outflows_reconciliation` | `${__url_time_range}` |
| `transaction-analysis-dashboard` | `executive_dashboard`, `category-spending-v2`, `outflows_insights`, `outflows_reconciliation` | `${__url_time_range}`, `time_window` |
| `category-spending-dashboard` | `transaction_analysis_dashboard` | `${__url_time_range}`, `time_window` |

When adding a new cross-dashboard link, always include `?orgId=1&${__url_time_range}` as a minimum. If the destination dashboard declares `time_window` or `dashboard_period` variables, pass them via `&var-time_window=${time_window}` and `&var-dashboard_period=${dashboard_period}` respectively.
