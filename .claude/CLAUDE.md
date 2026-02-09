# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Claude Local Permissions
- `.claude/settings.local.json` is the allowlist that controls which shell commands Claude Code may execute when running locally.
- Keep the allow list tight and command-specific (prefer `docker-compose ps` over broad `docker*` globs).
- Never add commands that expose secrets or destructive actions; review and prune entries after one-off debugging sessions.
- If you broaden permissions, leave a short note in the Git history or PR describing why the new command is required.

## Project Overview

This is a personal finance data pipeline that processes QIF (Quicken Interchange Format) bank transaction files and displays financial insights through Grafana dashboards. The system runs on a home server and provides financial visualization for household budgeting.

**Tech Stack**: Dagster (orchestration), dbt (transformations), PostgreSQL (storage), Docker Compose (deployment), Python with UV workspace management.

**Operational context** — the pipeline runs on a manual, monthly cadence and dashboards are reviewed once or twice a quarter. See `.claude/pipeline-context.md` for the full picture and the guardrails Claude should follow when touching the pipeline or dashboards.

## Dashboard Layout Requirement

- Treat user-adjusted panel spacing, size, and placement (`gridPos`) as authoritative.
- Do not auto-reflow or re-pack dashboard layouts after functional edits.
- If a panel must move, keep changes minimal and preserve visual grouping and alignment established by the user.

## Development Commands

### Setup and Run
```bash
# Copy environment file and configure credentials
cp .env.template .env  # Edit with your database credentials

# Start all services
docker-compose up -d

# Access Dagster UI
# Navigate to http://localhost:3000
```

### Development Workflow
1. Place QIF files in `pipeline_personal_finance/qif_files/`
2. Access Dagster UI at localhost:3000
3. Reload definitions in Dagster UI
4. Run the asset pipeline
5. View results in Grafana dashboards

### Database Access
- PostgreSQL runs on port 5432
- Connection details in `.env` file
- Database: `personal_finance`
- Schemas: `landing`, `staging`, `transformation`, `reporting`

### Code Quality
```bash
# SQL linting (available via dev dependencies)
uv run sqlfluff lint pipeline_personal_finance/dbt_finance/models/
uv run sqlfluff fix pipeline_personal_finance/dbt_finance/models/
```

## Architecture

### Data Flow
1. **Landing Zone**: QIF files → PostgreSQL `landing` schema (raw ingestion via Dagster)
2. **Staging Layer**: Clean and standardize data (`staging` schema via dbt)
3. **Transformation Layer**: Business logic, categorization, balance adjustments (`transformation` schema)
4. **Reporting Layer**: Fact tables and visualization views (`reporting` schema)

### Project Structure
```
dagster_core/                    # Orchestration layer
pipeline_personal_finance/       # Main pipeline
  ├── dbt_finance/              # Data transformations
  │   ├── models/staging/       # Raw data staging
  │   ├── models/transformation/# Business logic
  │   ├── models/reporting/     # Final reporting models
  │   ├── macros/               # Custom dbt macros
  │   ├── seeds/                # Reference data (categories)
  │   └── snapshots/            # SCD tracking
  └── qif_files/                # Source transaction files
```

### Bank Integration
- Supports Australian banks: Adelaide Bank, Bendigo Bank, ING
- QIF file naming: `BankName_AccountName_Transactions_YYYYMMDD.qif`
- Automatic duplicate detection and incremental processing

## dbt Configuration

### Materializations
- **Staging**: Tables in `staging` schema
- **Transformation**: Tables in `transformation` schema
- **Reporting**: Tables in `reporting` schema

### Key Models
- Bank-specific staging models for each account type
- Balance adjustment and account consolidation logic
- Transaction categorization using seed data
- Visualization-ready fact tables

### Running dbt Commands
dbt commands should be executed within the containerized environment or by accessing the running `pipeline_personal_finance` container.

## Environment Configuration

### Required Environment Variables
- `DAGSTER_POSTGRES_HOST/USER/PASSWORD/PORT/DB`: Database connection
- `DAGSTER_DEPLOYMENT`: Set to `prod` or `dev`
- `TIMEZONE`: Australia/Melbourne
- `GRAFANA_USER/PASSWORD`: Reader access for dashboards

### Deployment Environments
- **Production**: Full Docker Compose stack with persistent volumes
- **Development**: Uses same containers with code volume mounts for live development

## Database Schemas

- **landing**: Raw QIF file ingestion
- **staging**: Cleaned and standardized bank data
- **transformation**: Business logic applied (categorization, balance adjustments)
- **reporting**: Final models for visualization

## Grafana Dashboards

### Currency Convention
- **Important**: Treat all monetary values as AUD by default.
- Do not display currency notation in dashboards: no `$`, no `AUD`, and no currency unit formatting.
- Use neutral numeric display formatting so values remain readable without an explicit currency label.

### Percentage Formatting Standards
- **Critical**: Always maintain consistency between SQL data format and Grafana display units
- **percentunit in Grafana**: Expects 0-1 ratio values (e.g., 0.25 for 25%)
  - SQL should provide values as decimals (not multiplied by 100)
  - Example: `savings_rate` = 0.25 (not 25.0)
- **percent in Grafana**: Expects 0-100 percentage values (e.g., 25 for 25%)
  - SQL should provide values already multiplied by 100
  - Example: `savings_rate_pct` = 25.0 (not 0.25)
- **Field Naming Convention**:
  - `field_name` = 0-1 ratio for percentunit display
  - `field_name_pct` = 0-100 percentage for percent display
- **Never** multiply by 100 in SQL for percentunit fields - this causes display errors like -8660%

### Pie Chart Configuration
- **Important**: For pie charts, always set "Show values" to display "All values" instead of just calculations
- In the dashboard JSON, add `"displayLabels": ["name", "value"]` to the options section
- Update legend values to `"values": ["value"]` to show actual values in the legend
- **Critical**: Set `"reduceOptions.values": true` to display actual values on pie chart segments
- This ensures pie charts display actual values on each segment, not just percentages or calculations

### Bar/Stat/Gauge Panels
- For bar gauges with multiple metrics, set Value option to "All values" (JSON: `options.reduceOptions.values = true`) so each metric is displayed.
- Use horizontal orientation for readability and keep height compact on full‑width rows.
- Choose percent units based on the data shape:
  - Ratio 0–1 → `percentunit` (set min/max to `-1..1` if negatives are possible).
  - Percent 0–100 → `percent` (set min/max to `-100..100` if negatives are possible).

More detailed guidance lives in `grafana/provisioning/dashboards/README.md`.

## Testing

Test files located in `dagster_finance_tests/` directory. Testing infrastructure is minimal and requires expansion for comprehensive coverage.

## Pre-Commit Dashboard Verification

Before committing changes that affect Grafana dashboards or dbt models, verify the dashboards are functioning correctly using Playwright.

### Planning Artifacts
- Log dashboard issues in `plan-fixes.md`.
- Log new feature ideas in `plan-features.md`.

### Dashboard Query Migration Checklist

When changing dashboard SQL sources (table/view/model migrations), verify all items below before merge:

- Table/view rename is applied in every affected panel query.
- Column renames are fully mapped (no stale legacy names left in SQL).
- Join keys are validated against active schema relations.
- Units and labels still match returned data shape.
- `scripts/check_grafana_dashboards.py` passes for impacted dashboard ranges.
- Live panel verification is captured (API run, screenshot, or equivalent evidence).

### Verification Process

1. **Navigate to Grafana**:
   - Production server: `http://192.168.1.103:3001`
   - Local development: `http://localhost:3001`
   - Credentials: Check with project owner (do not store in code)

2. **Review Key Dashboards**:
   - Executive Financial Overview - main KPIs and summary
   - Cash Flow Analysis - income/expense trends
   - Category Spending Analysis - spending breakdowns
   - Account Performance - balance tracking

3. **Verify Panel Data**:
   - All panels should display data (not "No data")
   - Check for console errors in browser (F12 > Console)
   - Common issues:
     - "default database not configured" = datasource misconfiguration
     - SQL syntax errors = check dbt model changes
     - Missing data = verify dbt models ran successfully

4. **Take Screenshot**:
   - Save to `screenshots/[task-name].png`
   - Document any issues found

5. **Update Activity Log**:
   - Append dated entry to `activity.md`
   - Include: task description, actions taken, findings, screenshot filename

### Using Playwright CLI (Preferred)

Use Playwright CLI for dashboard connectivity and screenshot checks.

```bash
# Install CLI (if needed)
npm install -g playwright

# Install browser runtime (if needed)
playwright install chromium

# Validate local dashboard route and capture evidence
playwright screenshot --browser=chromium http://localhost:3001/dashboards screenshots/playwright_dashboard_check.png
```

Latest local check (2026-02-08):
- Route tested: `http://localhost:3001/dashboards`
- Result: reachable but redirects to `/login` (`302 -> 200`)
- Evidence: `screenshots/playwright_dashboard_check.png`

### Troubleshooting Database Connection

If dashboards show "No data":
1. Verify PostgreSQL is running: `docker-compose ps`
2. Check datasource config: `grafana/provisioning/datasources/postgres.yml`
3. Test database connection: `docker-compose exec dagster_postgres psql -U postgres -d personal_finance`
4. Verify dbt models exist: Check `reporting` schema for expected tables
