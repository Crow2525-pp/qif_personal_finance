# Foreign Key Constraints Setup

This document explains the foreign key constraint system implemented for the personal finance dbt project using dbt's native constraint configuration.

## Overview

Foreign key constraints ensure referential integrity between fact tables and their corresponding dimension tables. They prevent orphaned records and maintain data consistency. This implementation uses dbt's native constraint configuration with contracts enforcement rather than post-hooks.

## Implemented Constraints

### Core Relationships

1. **`fact_transactions_enhanced` → `dim_accounts_enhanced`**
   - **Constraint**: `fk_fact_transactions_account`  
   - **Relationship**: `fact_transactions_enhanced.account_key` → `dim_accounts_enhanced.account_key`
   - **Rules**: ON DELETE RESTRICT, ON UPDATE CASCADE

2. **`fact_transactions_enhanced` → `dim_categories_enhanced`**
   - **Constraint**: `fk_fact_transactions_category`
   - **Relationship**: `fact_transactions_enhanced.category_key` → `dim_categories_enhanced.category_key`  
   - **Rules**: ON DELETE RESTRICT, ON UPDATE CASCADE

3. **`fact_daily_balances` → `dim_accounts_enhanced`**
   - **Constraint**: `fk_fact_daily_balances_account`
   - **Relationship**: `fact_daily_balances.account_key` → `dim_accounts_enhanced.account_key`
   - **Rules**: ON DELETE RESTRICT, ON UPDATE CASCADE

## Native Constraint Configuration

Constraints are now defined using dbt's native constraint configuration in `models/reporting/schema.yml`. This approach:
- Uses `contract: {enforced: true}` to enable data contracts
- Defines constraints directly in the model schema
- Automatically enforced during model builds
- Provides better integration with dbt Core functionality

### Schema Configuration Example
```yaml
models:
  - name: fact_transactions_enhanced
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

## Management Commands

### Check Current Constraint Status
```bash
dbt run-operation check_constraint_status
```

### Validate Constraint Integrity
```bash
dbt run-operation validate_constraint_integrity
```

### Build Models with Constraints
Native constraints are automatically applied when building models with contracts enabled:
```bash
# Build dimension models first (they don't have foreign key dependencies)
dbt run --models dim_accounts_enhanced dim_categories_enhanced

# Build fact tables (constraints will be applied automatically)
dbt run --models fact_transactions_enhanced fact_daily_balances
```

Note: The legacy macro-based constraint management commands (`manage_constraints`) are deprecated in favor of the native constraint approach.

## Data Quality Tests

The system includes automated tests to ensure referential integrity:

### `test_foreign_key_constraints.sql`
- Tests all FK relationships for orphaned records
- Fails if any fact table records reference non-existent dimension records
- Run with: `dbt test --select test_foreign_key_constraints`

### `test_constraint_existence.sql`  
- Verifies that all expected FK constraints exist in the database
- Fails if constraints are missing from the database schema
- Run with: `dbt test --select test_constraint_existence`

## Build Process Integration

### Standard Build with Native Constraints
```bash
# Build dimensional models first
dbt run --models dim_accounts_enhanced dim_categories_enhanced

# Build fact tables (constraints are automatically applied)
dbt run --models fact_transactions_enhanced fact_daily_balances
```

### Full Build with Validation
```bash
# Build all reporting models
dbt run --models reporting.dim_accounts_enhanced reporting.dim_categories_enhanced
dbt run --models reporting.fact_transactions_enhanced reporting.fact_daily_balances

# Run constraint validation tests
dbt test --select test_foreign_key_constraints test_constraint_existence

# Check final status
dbt run-operation check_constraint_status
```

### Troubleshooting Contract Failures
If model builds fail due to contract validation:
```bash
# Check the specific error in dbt logs
dbt run --models fact_transactions_enhanced --log-level debug

# Temporarily disable contracts for debugging (not recommended for production)
# Remove contract.enforced: true from schema.yml temporarily
```

## Constraint Rules Explained

### ON DELETE RESTRICT
- Prevents deletion of dimension records that are referenced by fact records
- Example: Cannot delete an account from `dim_accounts_enhanced` if transactions exist for it

### ON UPDATE CASCADE  
- Automatically updates foreign key values in fact tables when primary key values change in dimension tables
- Example: If an `account_key` changes in `dim_accounts_enhanced`, it's automatically updated in all referencing fact tables

## Troubleshooting

### Constraint Creation Fails
1. **Check for orphaned records**: Run `dbt run-operation validate_constraint_integrity`
2. **Fix data quality issues**: Ensure all foreign key values exist in parent tables
3. **Retry constraint creation**: Run `dbt run-operation manage_constraints --args '{operation: recreate}'`

### Build Fails Due to Constraints
1. **Temporarily drop constraints**: `dbt run-operation manage_constraints --args '{operation: drop}'`
2. **Fix underlying data issues**
3. **Rebuild models**: `dbt run --models <affected_models>`
4. **Re-add constraints**: `dbt run-operation manage_constraints --args '{operation: add}'`

### Performance Impact
- FK constraints add overhead to INSERT/UPDATE/DELETE operations
- Constraints are checked on every DML operation
- For large batch loads, consider temporarily dropping constraints during load and re-adding afterward

## Best Practices

1. **Build dimensions first**: Always build dimension tables before fact tables
2. **Test regularly**: Run constraint validation tests as part of CI/CD pipeline  
3. **Monitor performance**: Watch for constraint-related performance impacts during large data loads
4. **Document relationships**: Keep this documentation updated as new relationships are added

## Adding New Constraints

To add new foreign key constraints:

1. **Update the constraint list** in `macros/add_foreign_key_constraints.sql`
2. **Add corresponding drop logic** in `macros/drop_foreign_key_constraints.sql`  
3. **Update validation tests** in `tests/test_foreign_key_constraints.sql`
4. **Add post-hook** to the relevant fact table model
5. **Update this documentation**

## Monitoring

Regular monitoring commands:
```bash
# Daily check - run after any data loads
dbt run-operation validate_constraint_integrity

# Weekly check - full status review  
dbt run-operation check_constraint_status

# Monthly check - full test suite
dbt test --select test_foreign_key_constraints test_constraint_existence
```