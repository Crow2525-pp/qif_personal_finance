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

## Dashboard QA Harness

Use the quality gate script to run lint, live Grafana API checks, and optional Playwright screenshots in one command.

### Local usage

```bash
# lint + live checks (default thresholds: 0 for failures/warnings)
python scripts/dashboard_quality_gate.py --dashboards executive_dashboard category-spending-v2

# include screenshot evidence (requires Playwright + GRAFANA_PASSWORD)
python scripts/dashboard_quality_gate.py --dashboards executive_dashboard --screenshots

# lint-only mode (no Grafana connectivity required)
python scripts/dashboard_quality_gate.py --lint-only
```

Artifacts are written to `artifacts/dashboard-quality/<UTC timestamp>/` and include:
- checker raw output (`lint-only.*`, `live-checks.*`)
- normalized findings (`findings.normalized.json`)
- markdown report (`report.md`)
- screenshots (`screenshots/*.png`) when `--screenshots` is enabled

### CI usage

```bash
python scripts/dashboard_quality_gate.py \
  --base-url "$GRAFANA_URL" \
  --dashboards executive_dashboard cash_flow_analysis \
  --max-failing-panels 0 \
  --max-layout-warnings 5 \
  --max-static-warnings 5 \
  --max-parity-warnings 0
```

The script exits non-zero when any threshold is exceeded or static lint parse errors are detected.

### Visual checks

When `--screenshots` is enabled, the quality gate also performs DOM-level visual inspection on each loaded dashboard page. These checks catch rendering failures that the API cannot detect:

| Check | Selector / source | Severity | What it catches |
|---|---|---|---|
| No data overlays | `[data-testid="data-testid Panel status message"]`, `.panel-empty` | warning | Panels showing "No data" due to column mismatches, missing time columns, or empty result sets |
| Panel errors | `[data-testid="data-testid Panel status error"]`, `[data-testid="data-testid Panel header error icon"]` | error | Panels with query errors, datasource failures, or rendering exceptions |
| Console errors | Browser console messages at `error` level | warning | JavaScript errors, failed API calls, or plugin issues (benign patterns like `favicon`, `grafana-usage-stats`, `api/live/ws` are excluded) |

Findings appear in `findings.normalized.json` with `source: "visual"` and in the report under **Visual Check Findings**.

Use `--max-visual-warnings <N>` to set the threshold (default: 0). Set a higher value when known "No data" panels are expected:

```bash
python scripts/dashboard_quality_gate.py --screenshots --max-visual-warnings 10
```

## Unit and Sign Standards

These standards are enforced across all 23 dashboard files as of task-48.

### Monetary values

Use `"unit": "short"` for all monetary amounts. Do **not** use `currencyAUD`, `currencyUSD`, or `currencyGBP` — Grafana 12 renders these as a raw suffix (e.g. "12.8 KAUD") instead of the intended symbol.

```json
// CORRECT
"unit": "short"

// WRONG - broken in Grafana 12
"unit": "currencyUSD"
"unit": "currencyAUD"
```

Values display as "12.8 K", "-528 K", etc., which is clean and currency-neutral for AUD.

### Ratio values (0-1 range)

Use `"unit": "percentunit"` with explicit `min` and `max` bounds:

```json
"unit": "percentunit",
"min": -1,
"max": 1
```

The `min`/`max` are required — without them Grafana auto-scales and small ratios may appear as near-zero on gauges. If the field can never be negative (e.g. an expense ratio), use `"min": 0, "max": 1`.

SQL must supply raw ratio values (e.g. `0.25` for 25%). Do **not** multiply by 100 in SQL for `percentunit` fields — this causes display errors like `-8660%`.

Field naming convention: bare name (e.g. `savings_rate`) = 0-1 ratio for `percentunit`.

### Percentage values (0-100 range)

Use `"unit": "percent"` with explicit bounds:

```json
"unit": "percent",
"min": -100,
"max": 100
```

SQL must supply values already multiplied by 100 (e.g. `25.0` for 25%). If negative values are impossible, use `"min": 0, "max": 100`.

Field naming convention: `_pct` suffix (e.g. `savings_rate_pct`) = 0-100 value for `percent`.

### Sign convention for expenses

Expenses should be displayed as **positive magnitudes** in expense-specific panels so "Expenses: 14.8 K" is shown, not "-14.8 K". Negate the value in SQL when needed:

```sql
-- If transaction_amount stores outflows as negative, negate for display:
ABS(total_expenses) AS expenses
```

Only show negative values when displaying net cash flow or change direction.

### Sign convention for liabilities

Show liabilities as **positive magnitudes** in dedicated liability/debt panels. Negate only when computing net worth (`assets - liabilities`).

### Before / after examples

| Context | Before (broken) | After (correct) |
|---|---|---|
| Account balance panel | `"unit": "currencyUSD"` | `"unit": "short"` |
| Savings rate gauge | `"unit": "percentunit"` (no min/max) | `"unit": "percentunit", "min": -1, "max": 1` |
| Expense ratio table | `"unit": "currencyAUD"` | `"unit": "short"` |
| MoM change gauge | `"unit": "percentunit"` (no min/max) | `"unit": "percentunit", "min": -1, "max": 1` |

---

## Other Conventions
- Percent data: ratio fields (0-1) use `percentunit`; percentage fields (0-100) use `percent`; name ratio fields without `_pct`, add `_pct` suffix for 0-100 values.
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
