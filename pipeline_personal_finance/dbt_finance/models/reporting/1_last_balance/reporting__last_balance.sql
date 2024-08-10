WITH RANKEDBALANCES AS (
    SELECT
        account_name,
        CATEGORY,
        SUBCATEGORY,
        DATE,
        ADJUSTED_BALANCE,
        -- Rank for the most recent transaction
        ROW_NUMBER() OVER (PARTITION BY account_name, EXTRACT(YEAR FROM DATE) ORDER BY DATE DESC) AS RN_YEAR,
        ROW_NUMBER() OVER (PARTITION BY account_name, EXTRACT(YEAR FROM DATE), EXTRACT(QUARTER FROM DATE) ORDER BY DATE DESC) AS RN_QUARTER,
        ROW_NUMBER() OVER (PARTITION BY account_name, EXTRACT(YEAR FROM DATE), EXTRACT(MONTH FROM DATE) ORDER BY DATE DESC) AS RN_MONTH,
        ROW_NUMBER() OVER (PARTITION BY account_name, EXTRACT(YEAR FROM DATE), EXTRACT(WEEK FROM DATE) ORDER BY DATE DESC) AS RN_WEEK,
        ROW_NUMBER() OVER (PARTITION BY account_name, EXTRACT(YEAR FROM DATE), EXTRACT(MONTH FROM DATE), EXTRACT(DAY FROM DATE) ORDER BY DATE DESC) AS RN_DAY

    FROM
        {{ ref("trans_no_int_transfers") }}
)

SELECT
    account_name,
    CATEGORY,
    SUBCATEGORY,
    DATE AS PERIODSTART,
    ADJUSTED_BALANCE AS LATESTBALANCE,
    CASE
        WHEN RN_DAY = 1 THEN 'Day'
        WHEN RN_WEEK = 1 THEN 'Week'
        WHEN RN_MONTH = 1 THEN 'Month'
        WHEN RN_QUARTER = 1 THEN 'Quarter'
        WHEN RN_YEAR = 1 THEN 'Year'
        -- For safety, though each row should fit one of the above categories
    END AS PERIODTYPE
FROM
    RANKEDBALANCES
WHERE
    -- Ensuring it's the latest for any period
    RN_DAY = 1 OR RN_WEEK = 1 OR RN_MONTH = 1 OR RN_QUARTER = 1 OR RN_YEAR = 1
