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
