
-- models/date_calendar.sql

{{ config(materialized='table') }}

WITH RECURSIVE date_series AS (
    SELECT
        '2015-01-01'::date as date -- Start date explicitly cast to date
    UNION ALL
    SELECT
        (date + INTERVAL '1 day')::date as date -- Ensure recursive part also explicitly casts to date
    FROM date_series
    WHERE
        date < '2030-12-31'::date -- End date explicitly cast to date
)

SELECT
    date
FROM
    date_series
