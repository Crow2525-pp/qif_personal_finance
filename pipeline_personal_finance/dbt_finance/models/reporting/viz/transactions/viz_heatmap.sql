SELECT
    EXTRACT(YEAR FROM cal.date) AS year,
    ft.transaction_direction,
    ft.account_key,
    ft.category_key,
    SUM(ft.transaction_amount) FILTER (WHERE cal.month_short = 'Jan') AS "Jan",
    SUM(ft.transaction_amount) FILTER (WHERE cal.month_short = 'Feb') AS "Feb",
    SUM(ft.transaction_amount) FILTER (WHERE cal.month_short = 'Mar') AS "Mar",
    SUM(ft.transaction_amount) FILTER (WHERE cal.month_short = 'Apr') AS "Apr",
    SUM(ft.transaction_amount) FILTER (WHERE cal.month_short = 'May') AS "May",
    SUM(ft.transaction_amount) FILTER (WHERE cal.month_short = 'Jun') AS "Jun",
    SUM(ft.transaction_amount) FILTER (WHERE cal.month_short = 'Jul') AS "Jul",
    SUM(ft.transaction_amount) FILTER (WHERE cal.month_short = 'Aug') AS "Aug",
    SUM(ft.transaction_amount) FILTER (WHERE cal.month_short = 'Sep') AS "Sep",
    SUM(ft.transaction_amount) FILTER (WHERE cal.month_short = 'Oct') AS "Oct",
    SUM(ft.transaction_amount) FILTER (WHERE cal.month_short = 'Nov') AS "Nov",
    SUM(ft.transaction_amount) FILTER (WHERE cal.month_short = 'Dec') AS "Dec"
FROM
    {{ ref('fct_transactions_enhanced') }} AS ft
LEFT JOIN
    {{ ref('dim_date_calendar') }} AS cal ON ft.transaction_date = cal.date
GROUP BY
    1,2,3,4
ORDER BY
    1,2,3,4
