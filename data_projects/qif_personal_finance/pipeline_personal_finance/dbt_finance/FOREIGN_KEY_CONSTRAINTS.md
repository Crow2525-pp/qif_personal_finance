# Foreign Key Constraints Setup

This project uses dbt’s native constraints with enforced contracts to define and validate foreign key relationships. No custom add/drop constraint macros are used.

## Overview

Foreign keys ensure referential integrity between fact and dimension tables. Relationships are declared in `models/reporting/schema.yml` and enforced during builds.

## Implemented Relationships

1. `fct_transactions_enhanced.account_key` → `dim_accounts_enhanced.account_key`
2. `fct_transactions_enhanced.category_key` → `dim_categories_enhanced.category_key`
3. `fct_daily_balances.account_key` → `dim_accounts_enhanced.account_key`

## Declaring Constraints (schema.yml)

Example snippet:
```yaml
models:
  - name: fct_transactions_enhanced
    config:
      contract:
        enforced: true
    constraints:
      - type: primary_key
        columns: [transaction_key]
      - type: foreign_key
        columns: [account_key]
        to: ref('dim_accounts_enhanced')
        to_columns: [account_key]
```

## Build and Validate

- Build models and run tests:
```bash
dbt build
dbt test --select test_foreign_key_constraints
```

Notes:
- Physical FK creation and naming are adapter‑specific. Rely on dbt constraints for portability and on data tests for integrity checks.
- If a build fails due to contracts, fix upstream data or model definitions to satisfy the declared constraints.

## Best Practices
- Ensure dimensions are defined before facts (dbt’s graph orders them correctly).
- Keep constraints and contracts co‑located with models in `schema.yml` for clarity.
