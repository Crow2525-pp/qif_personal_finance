{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['budget_year_month'], 'unique': false},
      {'columns': ['category_name'], 'unique': false}
    ]
  )
}}

WITH category_monthly AS (
  SELECT
    ft.transaction_year,
    ft.transaction_month,
    ft.transaction_year || '-' || LPAD(ft.transaction_month::TEXT, 2, '0') AS budget_year_month,
    dc.level_1_category,

    SUM(CASE WHEN {{ metric_expense(false, 'ft', 'dc') }} > 0 THEN {{ metric_expense(false, 'ft', 'dc') }} ELSE 0 END) AS category_expenses,
    COUNT(*) AS transaction_count,
    MIN(ft.transaction_date) AS month_start,
    MAX(ft.transaction_date) AS month_end

  FROM {{ ref('fct_transactions') }} ft
  LEFT JOIN {{ ref('dim_categories') }} dc
    ON ft.category_key = dc.category_key
  WHERE dc.level_1_category IS NOT NULL
  GROUP BY ft.transaction_year, ft.transaction_month, dc.level_1_category
),

category_with_targets AS (
  SELECT
    budget_year_month,
    level_1_category,
    category_expenses,
    transaction_count,

    -- Rolling 3-month average as target
    AVG(category_expenses) OVER (
      PARTITION BY level_1_category
      ORDER BY transaction_year, transaction_month
      ROWS BETWEEN 3 PRECEDING AND 1 PRECEDING
    ) AS target_expenses,

    -- Rank category by current month spending
    ROW_NUMBER() OVER (
      PARTITION BY budget_year_month
      ORDER BY category_expenses DESC
    ) AS spending_rank,

    transaction_year,
    transaction_month

  FROM category_monthly
),

category_variance AS (
  SELECT
    budget_year_month,
    level_1_category,
    category_expenses,
    ROUND(target_expenses, 2) AS target_expenses,
    transaction_count,
    spending_rank,

    CASE WHEN target_expenses > 0
      THEN ROUND(category_expenses - target_expenses, 2)
      ELSE 0
    END AS variance_delta,

    CASE WHEN target_expenses > 0
      THEN ROUND(((category_expenses - target_expenses) / target_expenses) * 100, 1)
      ELSE 0
    END AS variance_pct,

    -- Over/Under indicator
    CASE
      WHEN target_expenses = 0 THEN 'No Target'
      WHEN category_expenses > target_expenses * 1.1 THEN 'Over Budget'
      WHEN category_expenses < target_expenses * 0.9 THEN 'Under Budget'
      ELSE 'On Budget'
    END AS budget_status,

    -- Heatmap color indicator
    CASE
      WHEN target_expenses = 0 THEN 0  -- Neutral gray
      WHEN category_expenses > target_expenses * 1.2 THEN 3  -- Dark red (significantly over)
      WHEN category_expenses > target_expenses * 1.1 THEN 2  -- Light red (over)
      WHEN category_expenses < target_expenses * 0.8 THEN -2  -- Light green (under)
      WHEN category_expenses < target_expenses * 0.9 THEN -1  -- Yellow (slightly under)
      ELSE 0  -- On budget (neutral)
    END AS heatmap_intensity,

    transaction_year,
    transaction_month

  FROM category_with_targets
)

SELECT
  budget_year_month,
  level_1_category AS category_name,
  category_expenses,
  target_expenses,
  variance_delta,
  variance_pct,
  budget_status,
  heatmap_intensity,
  transaction_count,
  spending_rank,

  -- Formatted values for display
  '$' || TO_CHAR(category_expenses::numeric, 'FM999,999,999') AS category_expenses_formatted,
  '$' || TO_CHAR(target_expenses::numeric, 'FM999,999,999') AS target_expenses_formatted,
  '$' || TO_CHAR(variance_delta::numeric, 'FM999,999,999') AS variance_delta_formatted,
  TO_CHAR(variance_pct, 'FM990.0') || '%' AS variance_pct_formatted,

  CURRENT_TIMESTAMP AS report_generated_at

FROM category_variance
WHERE
  to_date(budget_year_month || '-01', 'YYYY-MM-DD') < date_trunc('month', CURRENT_DATE)
  AND spending_rank <= 10  -- Focus on top 10 spending categories
ORDER BY budget_year_month DESC, category_expenses DESC
