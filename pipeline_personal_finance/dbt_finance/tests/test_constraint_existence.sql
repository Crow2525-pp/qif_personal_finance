-- Adapter-specific physical constraint names may vary.
-- This test verifies that required FK relationships exist, independent of names.

WITH expected_relationships AS (
  SELECT 'reporting'::text AS child_schema, 'fct_transactions'::text AS child_table,
         'account_key'::text AS child_column, 'reporting'::text AS parent_schema,
         'dim_accounts'::text AS parent_table, 'account_key'::text AS parent_column
  UNION ALL
  SELECT 'reporting','fct_transactions','category_key','reporting','dim_categories','category_key'
  UNION ALL
  SELECT 'reporting','fct_daily_balances','account_key','reporting','dim_accounts','account_key'
),

fk_catalog AS (
  SELECT
    tc.table_schema      AS child_schema,
    tc.table_name        AS child_table,
    kcu.column_name      AS child_column,
    ccu.table_schema     AS parent_schema,
    ccu.table_name       AS parent_table,
    ccu.column_name      AS parent_column
  FROM information_schema.table_constraints tc
  JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
   AND tc.table_schema   = kcu.table_schema
  JOIN information_schema.constraint_column_usage ccu
    ON ccu.constraint_name = tc.constraint_name
   AND ccu.table_schema   = tc.table_schema
  WHERE tc.constraint_type = 'FOREIGN KEY'
),

missing AS (
  SELECT e.*
  FROM expected_relationships e
  LEFT JOIN fk_catalog f
    ON e.child_schema  = f.child_schema
   AND e.child_table   = f.child_table
   AND e.child_column  = f.child_column
   AND e.parent_schema = f.parent_schema
   AND e.parent_table  = f.parent_table
   AND e.parent_column = f.parent_column
  WHERE f.child_table IS NULL
)

SELECT * FROM missing
