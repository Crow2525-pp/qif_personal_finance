WITH filtered_data AS (
    SELECT
        TO_CHAR(date, 'Mon-YYYY') AS year_month,
        trans.memo,
        SUM(amount) AS amount
    FROM {{ ref('reporting__fact_transactions') }} AS trans
    LEFT JOIN {{ ref('dim_category') }} AS cat
      ON trans.category_foreign_key = cat.origin_key
    WHERE
      UPPER(cat.internal_indicator) = 'EXTERNAL'
      AND UPPER(trans.amount_type) = 'CREDIT'
      AND UPPER(cat.category) = 'MORTGAGE'
    GROUP BY 1, 2
)
SELECT 
    REPLACE(REPLACE(memo, '''', ''), ' ', '_') AS memo,
    SUM(amount) AS amount
FROM filtered_data
GROUP BY 1
ORDER BY amount DESC
