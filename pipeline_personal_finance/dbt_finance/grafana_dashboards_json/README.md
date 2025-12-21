# Grafana Dashboards Guidelines

This repository stores provisioned Grafana dashboards as JSON in this folder. When editing or creating panels, follow these conventions to keep dashboards consistent and readable.

## Data source
- Use the Postgres datasource UID `PCC52D03280B7034C` for dbt models in the `reporting` schema.

## Units and scaling
- Currency fields: use `currencyUSD`.
- Percentages: choose the unit that matches the data shape.
  - Ratio (0–1): use `percentunit` and set panel min/max to `-1..1` if negative values are possible.
  - Percent (0–100): use `percent` and set panel min/max to `0..100` (or `-100..100` if negatives are possible).
- Savings rate panels:
  - If using `…_percent` (ratio 0–1) columns, set unit to `percentunit`.
  - If using `…_percent_pct` (0–100) columns, set unit to `percent`.

## Bar/Stat/Gauge panels
- Bar gauge with multiple metrics: set `options.reduceOptions.values = true` (UI: Value → “All values”) to display all series, not a single calculated value.
- If using a single value: use `reduceOptions.values = false` and appropriate `calcs` (e.g., `lastNotNull`).
- Prefer horizontal orientation for readability.
- Keep bar gauge height compact (e.g., `gridPos.h` around 5 for a full‑width row).

## Pie charts
- Show segment values, not only percentages:
  - Set `options.displayLabels` to include `name` and `value`.
  - Configure legend to show actual values as needed.

## Queries
- For uncategorized outflows panels, prefer the canonical view:
  - `reporting.viz_high_value_uncategorized_by_period` with `period_type = 'month'`.
  - This ensures example text and thresholds match the Top‑5 list and reconciled logic.

## Version control tips
- Keep JSON diffs focused (avoid Grafana auto‑reformat churn).
- Group related panel edits into a single commit with clear description.

## See also
- Top‑level CLAUDE.md for project overview and general dashboard notes.

