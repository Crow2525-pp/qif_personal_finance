-- Test that all transactions have been categorized or flagged as uncategorized
WITH transaction_categorization AS (
  SELECT 
    ft.transaction_key,
    ft.transaction_natural_key,
    ft.category_key,
    dc.category,
    dc.subcategory,
    CASE 
      WHEN ft.category_key IS NULL THEN 'MISSING_CATEGORY'
      WHEN dc.category = 'Uncategorized' THEN 'UNCATEGORIZED'
      ELSE 'CATEGORIZED'
    END AS categorization_status
  FROM {{ ref('fact_transactions_enhanced') }} ft
  LEFT JOIN {{ ref('dim_categories_enhanced') }} dc
    ON ft.category_key = dc.category_key
),

problematic_transactions AS (
  SELECT *
  FROM transaction_categorization  
  WHERE categorization_status = 'MISSING_CATEGORY'
)

SELECT *
FROM problematic_transactions