# dbt Standalone SQL Compiler

A Python script that compiles dbt models into standalone SQL queries with all dependencies inlined as nested CTEs (Common Table Expressions). The generated SQL can run directly on your database without relying on materialized dbt models.

## Features

- **Dependency Inlining**: Automatically inlines all upstream model dependencies as CTEs
- **CTE Flattening**: Handles complex nested WITH clauses by flattening them to top-level CTEs
- **Source-Only Queries**: Final SQL only references source tables and seeds, not materialized models
- **Model Substitution**: Override specific model dependencies with custom table references
- **Standalone Execution**: Generated SQL runs independently on the database without dbt

## Prerequisites

1. **Compile your dbt project first:**
   ```bash
   dbt compile
   ```
   This generates the `target/manifest.json` file with compiled SQL for all models.

2. **Python 3.7+** (already available in your environment)

## Usage

### Basic Usage

Compile a single model:
```bash
python3 compile_standalone_sql.py <model_name>
```

Example:
```bash
python3 compile_standalone_sql.py fct_transactions
```

This outputs the standalone SQL to stdout.

### Save to File

```bash
python3 compile_standalone_sql.py fct_transactions --output my_query.sql
```

### Run on Database

```bash
# Generate and save
python3 compile_standalone_sql.py fct_transactions --output /tmp/query.sql

# Execute on PostgreSQL
psql -h localhost -p 5432 -U postgres -d personal_finance -f /tmp/query.sql
```

### Model Substitution

Use a configuration file to substitute specific models with alternative table references:

1. **Create a config file** (`substitutions.json`):
   ```json
   {
     "substitutions": {
       "model.personal_finance.dim_category": "reporting.dim_category",
       "model.personal_finance.int_categories": "custom_schema.my_categories"
     }
   }
   ```

2. **Run with config**:
   ```bash
   python3 compile_standalone_sql.py fct_transactions --config substitutions.json
   ```

This will:
- Exclude the substituted models from CTEs
- Reference the specified tables directly in the query
- Use this when you want to use materialized tables instead of inlining certain dependencies

### Custom Manifest Path

```bash
python3 compile_standalone_sql.py fct_transactions --manifest /path/to/manifest.json
```

## How It Works

1. **Reads dbt manifest.json**: Extracts dependency graph and compiled SQL
2. **Resolves dependencies**: Finds all upstream models in topological order
3. **Flattens nested CTEs**: Converts nested WITH clauses into top-level CTEs with prefixed names
4. **Replaces table references**: Updates all table references to use CTE names instead
5. **Generates standalone SQL**: Combines everything into a single executable query

### Example Transformation

**Original dbt model** (`fct_transactions.sql`):
```sql
SELECT * FROM {{ ref('int_categories') }}
LEFT JOIN {{ ref('dim_category') }} ON ...
```

**Generated standalone SQL**:
```sql
WITH
stg_adelaide_homeloan AS (
    SELECT ... FROM "personal_finance"."landing"."Adelaide_Homeloan_Transactions"
),

-- ... more CTEs for all dependencies ...

int_categories AS (
    SELECT ... FROM int_append_accounts
    LEFT JOIN dim_categorise_transaction ON ...
),

dim_category AS (
    SELECT ... FROM banking_categories
)

SELECT * FROM int_categories
LEFT JOIN dim_category ON ...
```

## CTE Flattening

The script handles complex nested WITH statements by flattening them. For example:

**Input** (model with internal CTEs):
```sql
WITH internal_cte AS (
    SELECT * FROM source
),
final AS (
    SELECT * FROM internal_cte
)
SELECT * FROM final
```

**Output** (flattened):
```sql
WITH
model_name__internal_cte AS (
    SELECT * FROM source
),
model_name__final AS (
    SELECT * FROM model_name__internal_cte
),
model_name AS (
    SELECT * FROM model_name__final
)

SELECT * FROM model_name
```

## Tested On

- **Simple models**: Models with 10-15 dependencies - Successfully tested on `fct_transactions`
- **Complex models**: Models with deeply nested CTEs and 15+ dependencies - Successfully tested on `fct_financial_projections`
- **Models with patches**: Handles union operations and seed data patches
- **Multi-level nesting**: Up to 3 levels of nested WITH statements

## Limitations

1. **Requires compiled models**: Must run `dbt compile` first to populate `compiled_code` in manifest
2. **No incremental models**: Works best with table and view materializations
3. **No macros**: Generated SQL is fully expanded - no dbt macros remain
4. **Performance**: Very large dependency trees may generate extremely long SQL files

## Troubleshooting

### Error: "Model not found in manifest"

Make sure you've compiled the dbt project:
```bash
dbt compile
```

### Error: "syntax error at or near {{""

Some models in the manifest don't have `compiled_code`. Recompile the entire project:
```bash
dbt compile  # Compiles all models
```

### Error: "relation does not exist"

The script may have failed to replace a table reference. Check:
1. Did you compile all dependencies?
2. Are there any custom SQL patterns the script doesn't handle?

Use the `--output` flag to inspect the generated SQL and identify which table reference wasn't replaced.

## Examples

### Example 1: Quick Query Execution

```bash
# Compile model and run immediately
python3 compile_standalone_sql.py fct_daily_balances | \
    psql -h localhost -p 5432 -U postgres -d personal_finance
```

### Example 2: Using Substitutions

```json
{
  "substitutions": {
    "model.personal_finance.dim_account": "reporting.dim_account",
    "model.personal_finance.dim_category": "reporting.dim_category"
  }
}
```

```bash
python3 compile_standalone_sql.py fct_transactions_enhanced \
    --config subs.json \
    --output enhanced_query.sql
```

This generates a query that uses the materialized `reporting.dim_account` and `reporting.dim_category` tables instead of inlining them as CTEs.

### Example 3: Testing Model Changes

When developing a new model, test the full compiled output:

```bash
# 1. Make changes to your model
# 2. Compile it
dbt compile --select +my_new_model

# 3. Generate standalone SQL
python3 compile_standalone_sql.py my_new_model --output test.sql

# 4. Test on database
psql -h localhost -p 5432 -U postgres -d personal_finance -f test.sql
```

## Benefits

1. **Debugging**: See the complete SQL with all dependencies inlined
2. **Portability**: Share queries that run without dbt infrastructure
3. **Performance Testing**: Test query performance without building all models
4. **Migration**: Export dbt logic as pure SQL for other tools
5. **Documentation**: Generate readable SQL documentation of complex model dependencies

## File Structure

```
compile_standalone_sql.py       # Main script
test_substitutions.json         # Example substitution config
README_STANDALONE_SQL.md        # This file
```

## Contributing

When modifying the script, test on both simple and complex models:

```bash
# Simple test
python3 compile_standalone_sql.py fct_transactions --output /tmp/simple.sql
psql -h localhost -p 5432 -U postgres -d personal_finance -f /tmp/simple.sql

# Complex test
python3 compile_standalone_sql.py fct_financial_projections --output /tmp/complex.sql
psql -h localhost -p 5432 -U postgres -d personal_finance -f /tmp/complex.sql
```

## License

This script is part of the personal_finance dbt project.
