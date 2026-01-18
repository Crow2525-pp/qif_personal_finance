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
