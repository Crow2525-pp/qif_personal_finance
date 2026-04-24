# Data Platform Workspace

This repository is no longer just the original personal-finance pipeline. It is a shared end-to-end data platform workspace plus data projects that run on that platform.

## Repository Layout

- `platform/` contains shared infrastructure: Dagster instance config, Postgres initialization, Grafana provisioning, and shared dashboards/datasources.
- `data_projects/qif_personal_finance/` contains the original QIF personal-finance data project. Its Dagster code location and dbt project live under `data_projects/qif_personal_finance/pipeline_personal_finance/`.
- `data_projects/coles_llm/` documents the Coles LLM shopper data project slot. The active local checkout is currently a separate nested Git repository at `coles-llm-shopper/`, so it is not imported into this repository by this restructure.
- `scripts/` contains repository-level operations for bootstrapping, deployment, dashboard checks, and maintenance.

The repository name still reflects its history (`qif_personal_finance`), but new source layout should follow the platform/data-project split above.

## Installation

1. Ensure Docker is installed and running.
2. Copy `.env.template` to `.env` and update it with your own credentials.
3. Run `make bootstrap-worktree` to materialize shared local QIF files and private seed files into this checkout.
4. Run `make up` and open the printed Dagster/Grafana URLs.
5. Reload Dagster definitions, then run the relevant asset/job.

## Preferred Run Path (Dagster First)

- Use `make dagster-run` to run QIF ingestion plus dbt in the supported order through Dagster.
- Direct dbt commands are break-glass only and require explicit opt-in:
  - `ALLOW_DIRECT_DBT=1 make dbt-build`
  - `ALLOW_DIRECT_DBT=1 make dbt-test`
- dbt project guardrails also block direct `dbt build/run/test` unless:
  - `DBT_EXECUTION_CONTEXT=dagster` (set automatically by Dagster), or
  - `ALLOW_DIRECT_DBT=1` (manual override).

## Database Role Model

- `postgres` remains the admin/superuser for manual operations.
- `dagster_service` is the application write role used by Dagster/dbt (INSERT/UPDATE/TRUNCATE/DDL, no DELETE).
- `grafanareader` is the Grafana query role (read-only on dashboard-facing data).

To apply role hardening to an existing running database:

```powershell
./scripts/apply-postgres-role-hardening.ps1 -DagsterPassword "<dagster service password>"
```

## Deployment (Remote Server)

For remote server deployment using the git-based workflow:

- Local development: work on your local machine, push to GitHub.
- Remote deployment: server pulls updates and rebuilds containers.
- See [scripts/DEPLOY.md](scripts/DEPLOY.md) for complete setup and workflow instructions.

Quick deploy on server:

```bash
cd /docker/appdata/qif_personal_finance
./scripts/portainer-deploy.sh
```

## Checking Grafana Dashboards For Data

If dashboards render with empty panels, run the helper script to confirm every SQL panel in Grafana returns rows.

1. Ensure Grafana is running (default http://localhost:3001 from `docker-compose.yml`).
2. Create a Grafana API token with at least `Viewer` access, or use your admin credentials.
3. Install dependencies: `uv sync`.
4. Run the checker (defaults to the last 365 days of data):
   - Using a token: `GRAFANA_URL=http://localhost:3001 GRAFANA_TOKEN=YOUR_TOKEN python scripts/check_grafana_dashboards.py --days 180`
   - Using user/pass: `GRAFANA_USER=admin GRAFANA_PASSWORD=... python scripts/check_grafana_dashboards.py --dashboard balance_dashboard`

The script queries every panel in each dashboard and reports panels that return no rows or SQL errors. It exits non-zero when a panel fails, so it can be wired into a post-provisioning step or CI job. Use `--dashboard` to limit the check to specific dashboard titles or UIDs.

Layout linting (titles vs. panel width) is included by default to catch headings that likely overflow their bounding boxes. To skip that check, add `--no-lint`. You can also tune the heuristic with `--lint-max-chars-per-col` (default 5) and `--lint-min-chars` (default 20).
