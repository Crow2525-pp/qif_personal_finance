# Activity Log

## 2026-01-16

### Grafana Dashboard Review

**Task**: Review Grafana dashboard and verify visuals are working as intended.

**Actions performed**:
- Started local HTTP server on port 8000
- Connected to Grafana at http://192.168.1.103:3001
- Logged in and navigated to the Executive Financial Overview dashboard
- Reviewed dashboard structure and panel configuration

**Findings**:
- All dashboard panels display "No data"
- Console errors indicate: "You do not currently have a default database configured for this datasource"
- The PostgreSQL datasource connection appears to be misconfigured or the database is not accessible

**Dashboard panels observed**:
- Executive Summary
- Financial Health Scores
- Key Executive KPIs
- Savings & Expense Performance
- Health & Risk KPIs
- Expense Control Score
- Monthly Financial Snapshot
- Cash Flow Trend (12 Months)
- Asset & Liability Snapshot
- Month-over-Month Cash Changes
- Month-over-Month Rate Changes
- AI Financial Insights
- Status Highlights
- How to Read This Dashboard (static content - working)

**Screenshot**: `screenshots/grafana-dashboard-review.png`

**Recommendation**: Check the Grafana datasource configuration and verify:
1. PostgreSQL service is running
2. Datasource credentials are correct in `grafana/provisioning/datasources/postgres.yml`
3. Database `personal_finance` exists with the required schemas (landing, staging, transformation, reporting)

---

### Grafana Datasource Fix & Local DuckDB Setup

**Task**: Fix Grafana dashboards to show data, set up local DuckDB development environment.

**Actions performed**:

1. **Merged feature/local-duckdb-grafana branch to main**
   - Contains local DuckDB development workflow
   - Includes synthetic data generation scripts
   - Dashboard validation scripts

2. **Fixed dim_accounts.sql PostgreSQL compatibility issue**
   - Issue: Using `account_name_lower` alias in the same SELECT where it was defined
   - Fix: Replaced alias references with `LOWER(account_name)` function calls
   - Commit: `b2557d8`

3. **Fixed Grafana PostgreSQL datasource configuration**
   - Issue: Grafana 10+ requires `database` field in `jsonData`, not root level
   - Fix: Moved `database: personal_finance` to `jsonData` section
   - Changed env var syntax from `${VAR}` to `$VAR`
   - Removed non-standard `searchPath` option
   - Commit: `54348f8`

4. **Updated docker-compose.local.yml for DuckDB plugin**
   - Changed from `GF_PLUGINS_PREINSTALL` to `GF_INSTALL_PLUGINS` format
   - Added `GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS` setting

5. **Tested local DuckDB development workflow**
   - Generated synthetic data (24 months)
   - Successfully ran all 85 dbt models against local DuckDB
   - Note: Grafana DuckDB plugin installation has compatibility issues with Grafana v12

**Files modified**:
- `pipeline_personal_finance/dbt_finance/models/marts/dim_accounts.sql`
- `grafana/provisioning/datasources/postgres.yml`
- `docker-compose.local.yml`

**Screenshot**: `screenshots/grafana-datasource-fix-pending.png`

**Next steps for production**:
1. Pull latest main on production server
2. Restart Grafana container: `docker compose restart grafana`
3. Verify dashboards display data correctly

---

### Local DuckDB Grafana Plugin Fix

**Task**: Validate local development environment works with Playwright.

**Actions performed**:

1. **Identified DuckDB plugin version issue**
   - docker-compose.local.yml referenced non-existent v1.1.1
   - Latest available version is v0.4.0
   - Fixed URL: `https://github.com/motherduckdb/grafana-duckdb-datasource/releases/download/v0.4.0/motherduck-duckdb-datasource-0.4.0.zip`

2. **Identified glibc compatibility issue**
   - DuckDB plugin requires glibc 2.35+ (Ubuntu 22.04+)
   - Default Grafana image is Alpine-based (uses musl libc)
   - Fix: Added `image: grafana/grafana:latest-ubuntu` to docker-compose.local.yml

3. **Validated DuckDB connection**
   - Datasource test: "Data source is working"
   - Successfully queried `personal_finance.reporting.fct_transactions` table
   - Data displayed correctly in Grafana Explore

**Known Limitation**:
- Tables with JSON columns (e.g., `rpt_executive_dashboard.top_spending_categories_json`) fail with:
  ```
  sql: Scan error on column index 54, name "top_spending_categories_json": unsupported Scan
  ```
- This is a DuckDB Grafana plugin limitation, not a data issue

**Files modified**:
- `docker-compose.local.yml` (plugin version + Ubuntu image)

**Screenshots**:
- `screenshots/local-duckdb-grafana-data.png` - Shows transaction data in Grafana Explore

**PR Created**: https://github.com/Crow2525-pp/qif_personal_finance/pull/9
