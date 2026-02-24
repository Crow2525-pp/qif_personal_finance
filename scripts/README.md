# Scripts

Utility scripts for managing the personal finance pipeline.

## validate_dashboard_json.py

Validates that all Grafana dashboard JSON files are parseable. This is the
upstream linter gate for other dashboard policy checks.

```bash
python scripts/validate_dashboard_json.py

# Machine-readable output
python scripts/validate_dashboard_json.py --json
```

Exit codes: `0` all files parse cleanly, `1` parse failures found,
`2` runtime/directory error.

---

## check_dashboard_time_control_policy.py

Validates Task 110 time-control policy across dashboard metadata, variables,
and links.

```bash
python scripts/check_dashboard_time_control_policy.py

# JSON output for CI/Dagster
python scripts/check_dashboard_time_control_policy.py --json

# Relax label strictness (keeps structural checks)
python scripts/check_dashboard_time_control_policy.py --no-strict
```

Exit codes: `0` policy pass, `1` policy violations, `2` parse/runtime error.

---

## check_grafana_dashboards.py

Validates Grafana dashboards for data issues and common configuration mistakes.
Two modes are supported:

### Live mode (default)

Connects to Grafana, executes every SQL query in each dashboard, and reports
panels that return no data or HTTP errors.

```bash
# Basic usage — all dashboards, last 365 days
GRAFANA_URL=http://localhost:3001 \
GRAFANA_USER=admin \
GRAFANA_PASSWORD=testadmin \
python scripts/check_grafana_dashboards.py

# Use an API token instead of user/password
GRAFANA_TOKEN=glsa_... python scripts/check_grafana_dashboards.py

# Narrow to specific dashboards and time range
python scripts/check_grafana_dashboards.py \
  --dashboard "Executive Financial Overview" --days 90

# Machine-readable JSON summary (exit 0 = all panels have data)
python scripts/check_grafana_dashboards.py --json
```

Exit codes: `0` all panels returned data, `1` one or more panels failed.

### Static lint mode (`--lint-only`)

Scans the dashboard JSON files on disk without a Grafana connection.
Intended for pre-commit hooks and CI gates.

```bash
python scripts/check_grafana_dashboards.py --lint-only

# Machine-readable JSON output for CI
python scripts/check_grafana_dashboards.py --lint-only --json
```

Exit codes: `0` all files parsed and linted cleanly (warnings only),
`1` at least one file has a JSON parse error.

### Static lint rules

| Rule | Description |
|------|-------------|
| `currency-unit` | `fieldConfig` unit set to `currencyAUD`, `currencyUSD`, `currencyGBP`, or `currencyEUR`. These are broken in Grafana 12 — use `short` instead. Checked in `defaults` and all `overrides`. |
| `current-date-timepicker` | A `stat`, `gauge`, `table`, `bargauge`, or other non-timeseries panel whose SQL contains `CURRENT_DATE` or `NOW()`. The panel ignores the dashboard time picker, which means the data is always anchored to wall-clock time. |
| `percentunit-missing-bounds` | `fieldConfig.defaults.unit` is `percentunit` but `min` or `max` are absent. Without bounds, Grafana cannot render a meaningful gauge range and negative values (e.g. negative savings rates) display incorrectly. |
| `parse-error` | Dashboard JSON file is not valid JSON (treated as a hard error). |

### Layout lint (included in both modes when Grafana is available)

Heuristic checks for titles that likely overflow their panel width and for
text panels whose content likely overflows their panel height.

### CI usage example

```yaml
# GitHub Actions excerpt
- name: Lint dashboard JSON
  run: python scripts/check_grafana_dashboards.py --lint-only --json | tee dashboard-lint.json
  # Exit 1 only on parse errors; warnings are non-blocking in lint-only mode
```

```bash
# Pre-commit hook (add to .git/hooks/pre-commit)
python scripts/check_grafana_dashboards.py --lint-only || exit 1
```

---

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
