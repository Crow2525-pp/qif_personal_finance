# Local Development (DuckDB + Grafana)

This workflow builds the dbt project locally against DuckDB using synthetic data, then validates Grafana dashboard SQL from the CLI.

## Goals
- Avoid any dependency on Postgres or server infrastructure.
- Generate reproducible synthetic data for all sources and seeds.
- Run all dbt models and tests locally.
- Validate Grafana dashboard queries against the DuckDB outputs.

## Prerequisites
- Python with dbt and the DuckDB adapter installed.
- DuckDB database file stored locally (gitignored).

Install dbt-duckdb (example):
```bash
python -m pip install dbt-duckdb
```

## Local profile
A DuckDB profile is stored in:
- `pipeline_personal_finance/dbt_finance/local_profiles/profiles.yml`

Use it by pointing dbt to this directory:
```bash
$env:DBT_PROFILES_DIR = "pipeline_personal_finance/dbt_finance/local_profiles"
```

Optionally override the DuckDB file path:
```bash
$env:DUCKDB_PATH = "pipeline_personal_finance/dbt_finance/duckdb/personal_finance.duckdb"
```

## Generate synthetic data
Synthetic seed CSVs are generated into:
- `pipeline_personal_finance/dbt_finance/seeds/local/`

These files are gitignored, so they do not interfere with other environments.

Run the generator:
```bash
python pipeline_personal_finance/dbt_finance/scripts/generate_synthetic_data.py --months 24
```

## Run dbt locally (DuckDB)
From the repo root:
```bash
$env:DBT_PROFILES_DIR = "pipeline_personal_finance/dbt_finance/local_profiles"
python -m dbt deps --project-dir pipeline_personal_finance/dbt_finance
python -m dbt seed --project-dir pipeline_personal_finance/dbt_finance
python -m dbt run --project-dir pipeline_personal_finance/dbt_finance
python -m dbt test --project-dir pipeline_personal_finance/dbt_finance
```

You can also run the full workflow with a single command:
```bash
powershell -File pipeline_personal_finance/dbt_finance/scripts/run_local_validation.ps1
```

## Validate Grafana dashboards from CLI
This script loads each dashboard JSON and executes its raw SQL against DuckDB:
```bash
python pipeline_personal_finance/dbt_finance/scripts/validate_grafana_dashboards.py
```

To fail on empty results:
```bash
python pipeline_personal_finance/dbt_finance/scripts/validate_grafana_dashboards.py --require-nonempty
```

Template defaults used during validation:
- `${dashboard_period}` -> `Latest`
- `$scenario` -> `full_time`

Compatibility views are built in `reporting` (during dbt run) to align older dashboard SQL with the dbt models.

## Grafana (optional local rendering)
Grafana can connect directly to the DuckDB file via the DuckDB datasource plugin.

1) Ensure the DuckDB file exists (after running dbt).
2) Start Grafana with the local override (from repo root):
```bash
docker compose -f docker-compose.yml -f docker-compose.local.yml up grafana -d
```
3) Open Grafana at:
- `http://localhost:3001`
4) Grafana will auto-provision a `DuckDB` datasource using:
- Path: `/var/lib/grafana/duckdb/personal_finance.duckdb`

The datasource config lives here:
- `grafana/provisioning_local/datasources/duckdb.yml`

## Notes
- Synthetic data is intentionally minimal but spans multiple months so dashboard queries return results.
- If you change model dependencies, update the generator to cover new required fields.
