WITH base AS (
  SELECT 
    cal.date,
    cal.month_short,
    EXTRACT(YEAR FROM cal.date) AS year,
    {{ metric_expense(false, 'ft', 'dc') }} AS expense_amount
  FROM {{ ref('fct_transactions') }} AS ft
  LEFT JOIN {{ ref('dim_date_calendar') }} AS cal
    ON ft.transaction_date = cal.date
  LEFT JOIN {{ ref('dim_categories') }} AS dc
    ON ft.category_key = dc.category_key
)
SELECT 
  year,
  SUM(expense_amount) FILTER (WHERE month_short = 'Jan') AS "Jan",
  SUM(expense_amount) FILTER (WHERE month_short = 'Feb') AS "Feb",
  SUM(expense_amount) FILTER (WHERE month_short = 'Mar') AS "Mar",
  SUM(expense_amount) FILTER (WHERE month_short = 'Apr') AS "Apr",
  SUM(expense_amount) FILTER (WHERE month_short = 'May') AS "May",
  SUM(expense_amount) FILTER (WHERE month_short = 'Jun') AS "Jun",
  SUM(expense_amount) FILTER (WHERE month_short = 'Jul') AS "Jul",
  SUM(expense_amount) FILTER (WHERE month_short = 'Aug') AS "Aug",
  SUM(expense_amount) FILTER (WHERE month_short = 'Sep') AS "Sep",
  SUM(expense_amount) FILTER (WHERE month_short = 'Oct') AS "Oct",
  SUM(expense_amount) FILTER (WHERE month_short = 'Nov') AS "Nov",
  SUM(expense_amount) FILTER (WHERE month_short = 'Dec') AS "Dec"
FROM base
GROUP BY year
ORDER BY year
