WITH grouped AS (
    SELECT
        TO_CHAR(ft.transaction_date, 'YYYY-MM') AS year_month,
        ft.account_key,
        ft.category_key,
        SUM({{ metric_expense(exclude_mortgage=true, table_alias='ft', category_alias='dc') }}) AS amount
    FROM {{ ref('fct_transactions_enhanced') }} ft
    LEFT JOIN {{ ref('dim_categories_enhanced') }} dc
      ON ft.category_key = dc.category_key
    GROUP BY 1, 2, 3
),

two_years AS (
    SELECT
        trans.year_month AS "Year Month",
        SUM(trans2.amount) AS "Month LY",
        SUM(trans.amount) AS "Month TY"
    FROM grouped AS trans
    LEFT JOIN grouped AS trans2
      ON trans.year_month = to_char(to_date(trans2.year_month, 'YYYY-MM') + INTERVAL '1 year', 'YYYY-MM')
     AND trans.account_key = trans2.account_key
     AND trans.category_key = trans2.category_key
    LEFT JOIN {{ ref('dim_categories_enhanced') }} AS dc
      ON trans.category_key = dc.category_key
    WHERE trans.amount > 0
    GROUP BY trans.year_month
),

rolling_totals AS (
    SELECT
        "Year Month",
        "Month LY" AS "Month LY",
        "Month TY" AS "Month TY",
        SUM("Month TY") OVER (
            ORDER BY to_date("Year Month", 'YYYY-MM')
            ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
        ) AS "R12M TY",
        SUM("Month LY") OVER (
            ORDER BY to_date("Year Month", 'YYYY-MM')
            ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
        ) AS "R12M LY"
    FROM two_years
)

SELECT
    to_timestamp("Year Month" || '-01', 'YYYY-MM-DD') AS date,
    "Month LY", "Month TY", "R12M TY", "R12M LY"
FROM rolling_totals
WHERE "Month LY" IS NOT NULL
ORDER BY date
