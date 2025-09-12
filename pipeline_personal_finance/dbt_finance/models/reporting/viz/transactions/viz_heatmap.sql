SELECT
    EXTRACT(YEAR FROM cal.date) AS year,
    amount_type,
    account_foreign_key,
    category_foreign_key,
    SUM(trans.amount) FILTER (WHERE cal.month_short = 'Jan') AS "Jan",
    SUM(trans.amount) FILTER (WHERE cal.month_short = 'Feb') AS "Feb",
    SUM(trans.amount) FILTER (WHERE cal.month_short = 'Mar') AS "Mar",
    SUM(trans.amount) FILTER (WHERE cal.month_short = 'Apr') AS "Apr",
    SUM(trans.amount) FILTER (WHERE cal.month_short = 'May') AS "May",
    SUM(trans.amount) FILTER (WHERE cal.month_short = 'Jun') AS "Jun",
    SUM(trans.amount) FILTER (WHERE cal.month_short = 'Jul') AS "Jul",
    SUM(trans.amount) FILTER (WHERE cal.month_short = 'Aug') AS "Aug",
    SUM(trans.amount) FILTER (WHERE cal.month_short = 'Sep') AS "Sep",
    SUM(trans.amount) FILTER (WHERE cal.month_short = 'Oct') AS "Oct",
    SUM(trans.amount) FILTER (WHERE cal.month_short = 'Nov') AS "Nov",
    SUM(trans.amount) FILTER (WHERE cal.month_short = 'Dec') AS "Dec"
FROM
    {{ ref("reporting__fact_transactions") }}  as trans
LEFT JOIN
    {{ ref("date_calendar") }}  as cal ON trans.date = cal.date
GROUP BY
    1,2,3,4
ORDER BY
    1,2,3,4