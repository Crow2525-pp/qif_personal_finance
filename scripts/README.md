# Scripts

Utility scripts for managing the personal finance pipeline.

## categorize_transactions.py

Interactive tool for categorizing uncategorized transactions. It prioritizes transactions by impact (total spend × count) so you can categorize the most transactions with the fewest questions.

### Features

- **Smart prioritization**: Asks about high-impact transaction groups first
- **Pattern matching**: One answer can categorize many similar transactions
- **Suggestions**: Shows AI-suggested categories based on similar categorized transactions
- **Direct integration**: Updates `banking_categories.csv` seed file directly

### Usage

```bash
# From project root, test database connection first
uv run python scripts/categorize_transactions.py --test-connection

# Run interactively (default: 20 questions)
uv run python scripts/categorize_transactions.py

# Limit number of questions
uv run python scripts/categorize_transactions.py --limit 10

# Preview without saving changes
uv run python scripts/categorize_transactions.py --dry-run

# Specify database host explicitly
uv run python scripts/categorize_transactions.py --host 192.168.1.103
```

### Running from the Server

If the database isn't accessible from your workstation, SSH into the server:

```bash
ssh user@192.168.1.103
cd /path/to/qif_personal_finance
uv run python scripts/categorize_transactions.py
```

### After Categorizing

After running the tool:

1. Review changes: `git diff pipeline_personal_finance/dbt_finance/seeds/local/banking_categories.csv`
2. Run dbt to apply: `cd pipeline_personal_finance/dbt_finance && dbt run`
3. Verify in Grafana dashboards

### How It Works

1. Queries uncategorized transactions from the database
2. Groups by normalized memo (removes dates, receipt numbers, etc.)
3. Ranks by impact score (transaction count × total spend)
4. Presents each group with suggested category if available
5. Writes new mappings to `banking_categories.csv`

The tool uses the same normalization logic as dbt's categorization models, so patterns you add will match the same transactions.

## check_grafana_dashboards.py

Panel-level Grafana smoke checker that executes dashboard SQL targets via Grafana API and fails when panels return errors or no data.

### Usage

```bash
# Check all dashboards
uv run python scripts/check_grafana_dashboards.py

# Check priority dashboards 1-10
uv run python scripts/check_grafana_dashboards.py --dashboard-range 1-10

# Check extended dashboards 11-23
uv run python scripts/check_grafana_dashboards.py --dashboard-range 11-23

# Include schema-qualified table/column validation
uv run python scripts/check_grafana_dashboards.py --dashboard-range 1-10 --schema-validate

# Run both core and extended sets in one command
uv run python scripts/check_grafana_dashboards.py --dashboard-range 1-10 --dashboard-range 11-23
```

### Notes

- Requires Grafana credentials via `GRAFANA_TOKEN` or `GRAFANA_USER`/`GRAFANA_PASSWORD`.
- Failure output includes panel title, target refId diagnostics, and extracted request IDs (for example `SQR113`) when present.
- CI smoke checks are gated in `.github/workflows/ci.yml` and run when:
  - manual dispatch sets `run_dashboard_smoke=true`, or
  - repository variable `RUN_GRAFANA_SMOKE=true`.
