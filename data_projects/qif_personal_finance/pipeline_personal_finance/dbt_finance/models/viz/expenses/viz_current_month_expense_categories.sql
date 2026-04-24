WITH last_month_cte AS (
  SELECT DATE_TRUNC('month', MAX(ft.transaction_date))::date AS last_month
  FROM {{ ref('fct_transactions') }} ft
),

monthly AS (
  SELECT 
    DATE_TRUNC('month', ft.transaction_date)::date AS month_start,
    dc.level_1_category AS category,
    SUM({{ metric_expense(false, 'ft', 'dc') }}) AS amount
  FROM {{ ref('fct_transactions') }} ft
  LEFT JOIN {{ ref('dim_categories') }} dc
    ON ft.category_key = dc.category_key
  GROUP BY 1, 2
),

allowed AS (
  SELECT category, display_order
  FROM {{ ref('categories_allowed') }}
),

base AS (
  SELECT 
    m.month_start,
    a.category,
    COALESCE(m.amount, 0) AS amount
  FROM allowed a
  LEFT JOIN monthly m
    ON m.category = a.category
),

joined AS (
  SELECT 
    b.category,
    lm.last_month,
    SUM(CASE WHEN b.month_start = lm.last_month THEN b.amount ELSE 0 END) AS last_month_amount,
    SUM(CASE WHEN b.month_start = (lm.last_month - INTERVAL '1 month')::date THEN b.amount ELSE 0 END) AS prev_month_amount,
    -- Last quarter (inclusive of last_month)
    SUM(CASE WHEN b.month_start >= (lm.last_month - INTERVAL '2 months')::date AND b.month_start <= lm.last_month THEN b.amount ELSE 0 END) AS last_qtr_amount,
    -- Previous quarter (the 3 months before last quarter)
    SUM(CASE WHEN b.month_start >= (lm.last_month - INTERVAL '5 months')::date AND b.month_start <= (lm.last_month - INTERVAL '3 months')::date THEN b.amount ELSE 0 END) AS prev_qtr_amount
  FROM base b
  CROSS JOIN last_month_cte lm
  GROUP BY 1, 2
),

final AS (
  SELECT 
    j.category,
    j.last_month,
    COALESCE(j.last_month_amount, 0) AS last_month_amount,
    COALESCE(j.prev_month_amount, 0) AS prev_month_amount,
    COALESCE(j.last_qtr_amount, 0) / 3.0 AS last_qtr_avg,
    COALESCE(j.prev_qtr_amount, 0) / 3.0 AS prev_qtr_avg,
    -- MoM change
    COALESCE(j.last_month_amount, 0) - COALESCE(j.prev_month_amount, 0) AS mom_change,
    CASE 
      WHEN COALESCE(j.prev_month_amount, 0) > 0 
      THEN ((COALESCE(j.last_month_amount, 0) - COALESCE(j.prev_month_amount, 0)) / COALESCE(j.prev_month_amount, 0))
      ELSE NULL 
    END AS mom_change_pct,
    -- vs prior quarter avg
    COALESCE(j.last_qtr_amount, 0) / 3.0 - COALESCE(j.prev_qtr_amount, 0) / 3.0 AS vs_prev_qtr_avg_change,
    CASE 
      WHEN COALESCE(j.prev_qtr_amount, 0) > 0
      THEN ((COALESCE(j.last_qtr_amount, 0) / 3.0) - (COALESCE(j.prev_qtr_amount, 0) / 3.0)) / (COALESCE(j.prev_qtr_amount, 0) / 3.0)
      ELSE NULL
    END AS vs_prev_qtr_avg_change_pct
  FROM joined j
)

SELECT 
  f.category,
  f.last_month AS period_date,
  TO_CHAR(f.last_month, 'YYYY-MM') AS year_month,
  f.last_month_amount,
  f.prev_month_amount,
  f.mom_change,
  f.mom_change_pct,
  f.last_qtr_avg,
  f.prev_qtr_avg,
  f.vs_prev_qtr_avg_change,
  f.vs_prev_qtr_avg_change_pct,
  -- Share of last month spending across categories
  CASE WHEN SUM(f.last_month_amount) OVER () > 0 
       THEN f.last_month_amount / SUM(f.last_month_amount) OVER ()
       ELSE 0 END AS last_month_share,
  -- Useful sorting fields
  RANK() OVER (ORDER BY f.last_month_amount DESC NULLS LAST) AS rank_by_last_month_spend
FROM final f
ORDER BY rank_by_last_month_spend, category
