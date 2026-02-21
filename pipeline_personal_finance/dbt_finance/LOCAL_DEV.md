# Local Development Guide

This file describes how to verify dashboard and dbt model changes locally before
committing. It also documents the SQL dialect differences between DuckDB (used for
offline synthetic-data runs) and PostgreSQL (the single source of truth for all
production data and all Grafana panels).

---

## Authoritative Local Verification Path

**Use the PostgreSQL path for all verification that must mirror production.**

The Grafana instance at `http://localhost:3001` is the single authoritative local
verification target. It connects directly to the production PostgreSQL database at
`192.168.1.103:5432` (see `grafana/provisioning/datasources/postgres.yml`). This
means every panel you see locally renders exactly the same SQL that runs in
production — there is no dialect gap.

The DuckDB path (described later in this file) is a secondary offline workflow
suitable only for synthetic-data smoke tests and dbt model unit testing. It must
not be treated as equivalent to the production path for dashboard verification.

### Quick check — does every panel return data?

```bash
# From the repo root. Needs the GRAFANA_TOKEN env var or user/password.
python scripts/check_grafana_dashboards.py \
  --base-url http://localhost:3001 \
  --user admin \
  --password testadmin \
  --days 365
```

The script:
- Calls the Grafana HTTP API and executes every `rawSql` target in each provisioned dashboard.
- Reports panels that come back empty or with errors.
- Lints panel titles for likely overflow (can be silenced with `--no-lint`).
- Exits non-zero when any panel fails, making it safe to wire into a pre-commit hook.

Filter to a single dashboard by title or UID:
```bash
python scripts/check_grafana_dashboards.py \
  --user admin --password testadmin \
  --dashboard "Executive Financial Overview"
```

### Full pre-commit verification checklist

1. Push dashboard JSON changes to the live Grafana instance:
   ```bash
   python scripts/push_grafana_dashboards.py
   ```
2. Run the panel check:
   ```bash
   python scripts/check_grafana_dashboards.py --user admin --password testadmin --days 365
   ```
3. Take a screenshot with Playwright for the activity log:
   ```bash
   playwright screenshot --browser=chromium \
     "http://localhost:3001/dashboards" \
     screenshots/pre-commit-check.png
   ```
4. Append a dated entry to `activity.md` with the screenshot filename and any
   issues found.

---

## Running dbt Against Production PostgreSQL Locally

The default `profiles.yml` at the repo root targets production PostgreSQL
(`192.168.1.103:5432`). Run dbt models directly against it from the project root:

```bash
# Uses profiles.yml --target prod (the default)
uv run dbt run --project-dir pipeline_personal_finance/dbt_finance
uv run dbt test --project-dir pipeline_personal_finance/dbt_finance
```

To run a single model:
```bash
uv run dbt run \
  --project-dir pipeline_personal_finance/dbt_finance \
  --select rpt_executive_dashboard
```

> **Important:** `docker exec dagster_postgres psql` connects to the container's
> internal PostgreSQL socket and can return stale or incomplete data. Always verify
> dbt output by querying `192.168.1.103:5432` directly (psycopg2, psql via the host
> network, or the Grafana check script).

---

## SQL Dialect Reference: DuckDB vs PostgreSQL

The dbt models use `{% if target.type == 'duckdb' %} ... {% else %} ... {% endif %}`
guards wherever the two dialects diverge. The table below shows every pattern
currently found in this codebase, plus the correct PostgreSQL equivalent to use in
ad-hoc queries and Grafana panel SQL.

### Date/time construction

| Intent | DuckDB | PostgreSQL |
|--------|--------|------------|
| Parse `'YYYY-MM-DD'` string to timestamp | `CAST(to_date(str, 'YYYY-MM-DD') AS TIMESTAMP)` | `to_timestamp(str, 'YYYY-MM-DD')` |
| Current month truncated to midnight | `date_trunc('month', current_date)` | `date_trunc('month', current_date)` |
| Add months | `+ interval '1 month'` | `+ interval '1 month'` (same) |
| Format date as string | `strftime(date, '%Y-%m')` | `TO_CHAR(date, 'YYYY-MM')` |

The production `rpt_executive_dashboard.sql` uses `TO_CHAR(CURRENT_DATE, 'YYYY-MM')`
at line 13 — this is PostgreSQL-only and will fail in DuckDB without the guard.

### Set-returning / series generation

| Intent | DuckDB | PostgreSQL |
|--------|--------|------------|
| Integer series 1..12 | `UNNEST(range(1, 13)) AS n` | `generate_series(1, 12) AS n` |
| Date series with step | `CROSS JOIN generate_series(start, end, interval) AS gs(month_start)` | `CROSS JOIN LATERAL generate_series(start, end, interval) AS gs` then `gs::date` |

Files affected: `projection_parameters.sql`, `int_property_assets_monthly.sql`.

Note that DuckDB's `generate_series` for dates returns a struct column and the
alias syntax differs from PostgreSQL's `LATERAL` form.

### String tokenisation (regexp split)

| Intent | DuckDB | PostgreSQL |
|--------|--------|------------|
| Split string to rows | `CROSS JOIN UNNEST(regexp_split_to_array(str, '\\s+')) AS tok(tok)` | `CROSS JOIN LATERAL regexp_split_to_table(str, '\\s+') AS tok` |

Files affected: `viz_high_value_uncategorized_by_period.sql`,
`suggested_banking_categories_export.sql`.

PostgreSQL's `regexp_split_to_table` is a set-returning function that must be used
with `LATERAL`. DuckDB uses `UNNEST` over the array form instead.

### JSON aggregation

| Intent | DuckDB | PostgreSQL |
|--------|--------|------------|
| Aggregate rows to JSON array | `to_json(list(json_object('k', v, ...)))` | `JSON_AGG(JSON_BUILD_OBJECT('k', v, ...) ORDER BY col)` |

File affected: `rpt_executive_dashboard.sql` (top_categories_json CTE).

### Array construction and filtering

| Intent | DuckDB | PostgreSQL |
|--------|--------|------------|
| Build array of nullable values | `[expr1, expr2, ...]` literal syntax | `ARRAY[expr1, expr2, ...]` |
| Filter nulls from array | `list_filter(arr, x -> x IS NOT NULL)` | `ARRAY_REMOVE(arr, NULL)` |

File affected: `rpt_financial_health_scorecard.sql` (financial_strengths,
areas_needing_attention columns).

### Contract enforcement

Two models disable dbt contract enforcement when the target is DuckDB because DuckDB
does not support all constraint types:

- `reporting/fct_daily_balances.sql`: `set enforce_contract = target.type != 'duckdb'`
- `marts/fct_transactions.sql`: `set enforce_contract = target.type != 'duckdb'`
- `reporting/budget/rpt_debt_reduction_tracking.sql`: `set unique_period = target.type != 'duckdb'`

These guards have no effect on production PostgreSQL runs and require no action.

---

## DuckDB Offline Workflow (Synthetic Data Only)

Use this path when you need to iterate on dbt models without a network connection
or before real transaction data is available. **Do not use DuckDB output to verify
Grafana dashboards** — the dialect guards produce different SQL than what production
executes, and the synthetic data does not reflect real account balances.

### Prerequisites

```bash
python -m pip install dbt-duckdb
```

### Configure the DuckDB profile

```powershell
$env:DBT_PROFILES_DIR = "pipeline_personal_finance/dbt_finance/local_profiles"
# Optionally override the database file location:
$env:DUCKDB_PATH = "pipeline_personal_finance/dbt_finance/duckdb/personal_finance.duckdb"
```

The profile is at `pipeline_personal_finance/dbt_finance/local_profiles/profiles.yml`
and targets `local_duckdb`.

### Generate synthetic seed data

```bash
python pipeline_personal_finance/dbt_finance/scripts/generate_synthetic_data.py --months 24
```

Synthetic CSVs land in `pipeline_personal_finance/dbt_finance/seeds/local/` which is
gitignored.

### Run dbt (DuckDB)

```bash
python -m dbt deps  --project-dir pipeline_personal_finance/dbt_finance
python -m dbt seed  --project-dir pipeline_personal_finance/dbt_finance
python -m dbt run   --project-dir pipeline_personal_finance/dbt_finance
python -m dbt test  --project-dir pipeline_personal_finance/dbt_finance
```

Or use the PowerShell helper:

```powershell
powershell -File pipeline_personal_finance/dbt_finance/scripts/run_local_validation.ps1
```

### CLI dashboard SQL smoke test (DuckDB only)

This script executes raw dashboard SQL directly against the DuckDB file. It is a
dialect-compatibility smoke test only — it does not verify Grafana rendering:

```bash
python pipeline_personal_finance/dbt_finance/scripts/validate_grafana_dashboards.py
python pipeline_personal_finance/dbt_finance/scripts/validate_grafana_dashboards.py --require-nonempty
```

Template variable substitutions applied during the run:
- `${dashboard_period}` -> `Latest`
- `$scenario` -> `full_time`

### DuckDB Grafana (optional, for DuckDB-path UI testing only)

Grafana can connect to the DuckDB file via the MotherDuck community plugin. This
requires the local compose override and produces a Grafana instance that uses
DuckDB-specific SQL — it is **not** the same as `http://localhost:3001`:

```bash
docker compose -f docker-compose.yml -f docker-compose.local.yml up grafana -d
```

Datasource config: `grafana/provisioning_local/datasources/duckdb.yml`
Database path inside container: `/var/lib/grafana/duckdb/personal_finance.duckdb`

> Because DuckDB Grafana uses the same datasource UID (`PCC52D03280B7034C`) as the
> production PostgreSQL datasource, do not run both compose stacks simultaneously or
> one will overwrite the other's datasource registration in Grafana's internal DB.

---

## Known Dialect Drift: Dashboard JSON

All dashboard JSON files in `grafana/provisioning/dashboards/` contain pure
PostgreSQL SQL. No DuckDB-specific syntax (`strftime`, `LIST_AGG`, `EPOCH`,
`list_filter`, `UNNEST(range(...))`) was found in any dashboard JSON as of
2026-02-21. The dialect guards exist only in the dbt Jinja layer.

If you add new dbt models that introduce DuckDB-only SQL, ensure the
`{% if target.type == 'duckdb' %}` guard is present and that the PostgreSQL branch
in the `{% else %}` block matches what the Grafana panel SQL expects.

---

## Summary: Which Path to Use

| Task | Path |
|------|------|
| Verify Grafana panels show real data | PostgreSQL via `http://localhost:3001` |
| Run `check_grafana_dashboards.py` | Against `http://localhost:3001` (PostgreSQL) |
| Push dashboard JSON changes | `scripts/push_grafana_dashboards.py` |
| Run dbt against production | `uv run dbt run` (default `prod` target) |
| Iterate on dbt models offline | DuckDB local profile + synthetic data |
| Unit-test dbt model SQL offline | DuckDB local profile |
| Verify Grafana panel SQL syntax only | `validate_grafana_dashboards.py` (DuckDB smoke test) |
