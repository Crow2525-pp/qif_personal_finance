-- Test that foreign key constraints actually exist in the database
WITH expected_constraints AS (
  SELECT 'fk_fact_transactions_account' AS constraint_name, 'reporting' AS schema_name, 'fact_transactions_enhanced' AS table_name
  UNION ALL
  SELECT 'fk_fact_transactions_category' AS constraint_name, 'reporting' AS schema_name, 'fact_transactions_enhanced' AS table_name
  UNION ALL  
  SELECT 'fk_fact_daily_balances_account' AS constraint_name, 'reporting' AS schema_name, 'fact_daily_balances' AS table_name
),

actual_constraints AS (
  SELECT 
    tc.constraint_name,
    tc.table_schema AS schema_name,
    tc.table_name
  FROM information_schema.table_constraints tc
  WHERE tc.constraint_type = 'FOREIGN KEY'
    AND tc.table_schema = 'reporting'
    AND tc.constraint_name IN (
      'fk_fact_transactions_account',
      'fk_fact_transactions_category', 
      'fk_fact_daily_balances_account'
    )
),

missing_constraints AS (
  SELECT 
    ec.constraint_name,
    ec.schema_name,
    ec.table_name,
    'Constraint does not exist in database' AS error_message
  FROM expected_constraints ec
  LEFT JOIN actual_constraints ac
    ON ec.constraint_name = ac.constraint_name
    AND ec.schema_name = ac.schema_name
    AND ec.table_name = ac.table_name
  WHERE ac.constraint_name IS NULL
)

-- Return missing constraints (test fails if any missing)
SELECT * FROM missing_constraints