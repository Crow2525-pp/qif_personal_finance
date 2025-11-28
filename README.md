# Introduction
- Use granfana to display finance information on a home assistant dashboard for wife & I to access
- Deploy on a home server and update QIF files (manually/periodically) to gain financial insights.

# Installation
1. ensure that docker is installed and running (windows)
2. replace sample.env with a .env and update with your own credentials
3. download qif files from bank and add them in pipeline_personal_finance\qif_files
4. run docker-compose up -d and then goto localhost:3000
5. reload the definitions and then run the asset.
6. [TBC]

# Checking Grafana dashboards for data
If dashboards render with empty panels, run the helper script to confirm every SQL panel in Grafana returns rows.

1. Ensure Grafana is running (default http://localhost:3001 from `docker-compose.yml`).
2. Create a Grafana API token with at least `Viewer` access, or use your admin credentials.
3. Install dependencies: `pip install -r requirements.txt`
4. Run the checker (defaults to the last 365 days of data):
   - Using a token: `GRAFANA_URL=http://localhost:3001 GRAFANA_TOKEN=YOUR_TOKEN python scripts/check_grafana_dashboards.py --days 180`
   - Using user/pass: `GRAFANA_USER=admin GRAFANA_PASSWORD=... python scripts/check_grafana_dashboards.py --dashboard balance_dashboard`

The script queries every panel in each dashboard and reports panels that return no rows or SQL errors. It exits non-zero when a panel fails, so it can be wired into a post-provisioning step or CI job. Use `--dashboard` to limit the check to specific dashboard titles or UIDs.
