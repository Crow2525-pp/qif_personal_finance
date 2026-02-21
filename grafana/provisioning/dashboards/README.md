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
