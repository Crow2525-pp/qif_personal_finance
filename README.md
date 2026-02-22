# Introduction
- Use granfana to display finance information on a home assistant dashboard for wife & I to access
- Deploy on a home server and update QIF files (manually/periodically) to gain financial insights.

# Installation
1. ensure that docker is installed and running (windows)
2. copy .env.template to .env and update with your own credentials
3. download qif files from bank and add them in pipeline_personal_finance\qif_files
4. run docker-compose up -d and then goto localhost:3000
5. reload the definitions and then run the asset.
6. [TBC]

# Preferred Run Path (Dagster First)
- Use `make dagster-run` to run ingestion + dbt in the supported order through Dagster.
- Direct dbt commands are break-glass only and require explicit opt-in:
  - `ALLOW_DIRECT_DBT=1 make dbt-build`
  - `ALLOW_DIRECT_DBT=1 make dbt-test`
- dbt project guardrails also block direct `dbt build/run/test` unless:
  - `DBT_EXECUTION_CONTEXT=dagster` (set automatically by Dagster), or
  - `ALLOW_DIRECT_DBT=1` (manual override).

# Deployment (Remote Server)
For remote server deployment using git-based workflow:
- **Local Development**: Work on your local machine, push to GitHub
- **Remote Deployment**: Server pulls updates and rebuilds containers
- See [scripts/DEPLOY.md](scripts/DEPLOY.md) for complete setup and workflow instructions

Quick deploy on server:
```bash
cd /docker/appdata/qif_personal_finance
./scripts/portainer-deploy.sh
```

# Checking Grafana dashboards for data
If dashboards render with empty panels, run the helper script to confirm every SQL panel in Grafana returns rows.

1. Ensure Grafana is running (default http://localhost:3001 from `docker-compose.yml`).
2. Create a Grafana API token with at least `Viewer` access, or use your admin credentials.
3. Install dependencies: `uv sync`
4. Run the checker (defaults to the last 365 days of data):
   - Using a token: `GRAFANA_URL=http://localhost:3001 GRAFANA_TOKEN=YOUR_TOKEN python scripts/check_grafana_dashboards.py --days 180`
   - Using user/pass: `GRAFANA_USER=admin GRAFANA_PASSWORD=... python scripts/check_grafana_dashboards.py --dashboard balance_dashboard`

The script queries every panel in each dashboard and reports panels that return no rows or SQL errors. It exits non-zero when a panel fails, so it can be wired into a post-provisioning step or CI job. Use `--dashboard` to limit the check to specific dashboard titles or UIDs.

Layout linting (titles vs. panel width) is included by default to catch headings that likely overflow their bounding boxes. If you want to skip that check, add `--no-lint`. You can also tune the heuristic with `--lint-max-chars-per-col` (default 5) and `--lint-min-chars` (default 20).
