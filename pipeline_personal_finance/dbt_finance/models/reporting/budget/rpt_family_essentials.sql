{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['budget_year_month'], 'unique': true}
    ]
  )
}}

/*
  Family Essentials Spending Summary
  Surfaces the non-negotiable costs for a family with young children:
  - Groceries (Food & Drink)
  - Family & Kids (childcare, activities, baby supplies)
  - Health & Beauty (medical, pharmacy, kids health)
  - Household essentials
*/

WITH monthly_family_spending AS (
  SELECT
    ft.transaction_year,
    ft.transaction_month,
    ft.transaction_year || '-' || LPAD(ft.transaction_month::TEXT, 2, '0') AS budget_year_month,
    dc.level_1_category,
    dc.level_2_subcategory,

    SUM({{ metric_expense(false, 'ft', 'dc') }}) AS category_spending,
    COUNT(*) AS transaction_count

  FROM {{ ref('fct_transactions') }} ft
  LEFT JOIN {{ ref('dim_categories') }} dc ON ft.category_key = dc.category_key
  WHERE dc.level_1_category IN ('Food & Drink', 'Family & Kids', 'Health & Beauty', 'Household & Services')
  GROUP BY
    ft.transaction_year,
    ft.transaction_month,
    dc.level_1_category,
    dc.level_2_subcategory
),

monthly_totals AS (
  SELECT
    budget_year_month,
    transaction_year,
    transaction_month,

    -- Groceries (Food & Drink category, typically groceries subcategory)
    SUM(CASE WHEN level_1_category = 'Food & Drink' THEN category_spending ELSE 0 END) AS groceries_spending,
    SUM(CASE WHEN level_1_category = 'Food & Drink' THEN transaction_count ELSE 0 END) AS groceries_transactions,

    -- Family & Kids (childcare, activities, supplies)
    SUM(CASE WHEN level_1_category = 'Family & Kids' THEN category_spending ELSE 0 END) AS family_kids_spending,
    SUM(CASE WHEN level_1_category = 'Family & Kids' THEN transaction_count ELSE 0 END) AS family_kids_transactions,

    -- Health & Medical
    SUM(CASE WHEN level_1_category = 'Health & Beauty' THEN category_spending ELSE 0 END) AS health_spending,
    SUM(CASE WHEN level_1_category = 'Health & Beauty' THEN transaction_count ELSE 0 END) AS health_transactions,

    -- Household essentials
    SUM(CASE WHEN level_1_category = 'Household & Services' THEN category_spending ELSE 0 END) AS household_spending,
    SUM(CASE WHEN level_1_category = 'Household & Services' THEN transaction_count ELSE 0 END) AS household_transactions,

    -- Total family essentials
    SUM(category_spending) AS total_family_essentials,
    SUM(transaction_count) AS total_transactions

  FROM monthly_family_spending
  GROUP BY budget_year_month, transaction_year, transaction_month
),

with_trends AS (
  SELECT
    mt.*,

    -- Month-over-month changes
    LAG(groceries_spending) OVER (ORDER BY transaction_year, transaction_month) AS prev_groceries,
    LAG(family_kids_spending) OVER (ORDER BY transaction_year, transaction_month) AS prev_family_kids,
    LAG(health_spending) OVER (ORDER BY transaction_year, transaction_month) AS prev_health,
    LAG(household_spending) OVER (ORDER BY transaction_year, transaction_month) AS prev_household,
    LAG(total_family_essentials) OVER (ORDER BY transaction_year, transaction_month) AS prev_total,

    -- 3-month rolling averages
    AVG(groceries_spending) OVER (
      ORDER BY transaction_year, transaction_month
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS avg_3m_groceries,
    AVG(family_kids_spending) OVER (
      ORDER BY transaction_year, transaction_month
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS avg_3m_family_kids,
    AVG(health_spending) OVER (
      ORDER BY transaction_year, transaction_month
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS avg_3m_health,
    AVG(total_family_essentials) OVER (
      ORDER BY transaction_year, transaction_month
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS avg_3m_total

  FROM monthly_totals mt
)

SELECT
  budget_year_month,
  transaction_year,
  transaction_month,

  -- Current month spending
  ROUND(groceries_spending::numeric, 2) AS groceries_spending,
  ROUND(family_kids_spending::numeric, 2) AS family_kids_spending,
  ROUND(health_spending::numeric, 2) AS health_spending,
  ROUND(household_spending::numeric, 2) AS household_spending,
  ROUND(total_family_essentials::numeric, 2) AS total_family_essentials,

  -- Transaction counts
  groceries_transactions,
  family_kids_transactions,
  health_transactions,
  household_transactions,
  total_transactions,

  -- Month-over-month changes
  ROUND((groceries_spending - COALESCE(prev_groceries, groceries_spending))::numeric, 2) AS groceries_mom_change,
  ROUND((family_kids_spending - COALESCE(prev_family_kids, family_kids_spending))::numeric, 2) AS family_kids_mom_change,
  ROUND((health_spending - COALESCE(prev_health, health_spending))::numeric, 2) AS health_mom_change,
  ROUND((total_family_essentials - COALESCE(prev_total, total_family_essentials))::numeric, 2) AS total_mom_change,

  -- 3-month averages
  ROUND(avg_3m_groceries::numeric, 2) AS avg_3m_groceries,
  ROUND(avg_3m_family_kids::numeric, 2) AS avg_3m_family_kids,
  ROUND(avg_3m_health::numeric, 2) AS avg_3m_health,
  ROUND(avg_3m_total::numeric, 2) AS avg_3m_total,

  -- Variance from average (for alerting)
  CASE
    WHEN avg_3m_total > 0
    THEN ROUND(((total_family_essentials - avg_3m_total) / avg_3m_total * 100)::numeric, 1)
    ELSE 0
  END AS variance_from_avg_pct,

  -- Cost per child estimate (assuming 3 children for this family)
  ROUND((total_family_essentials / 3)::numeric, 2) AS estimated_cost_per_child,

  CURRENT_TIMESTAMP AS report_generated_at

FROM with_trends
WHERE to_date(budget_year_month || '-01', 'YYYY-MM-DD') < date_trunc('month', CURRENT_DATE)
ORDER BY transaction_year DESC, transaction_month DESC
