-- models/date_calendar.sql

{{ config(materialized='table') }}

WITH RECURSIVE date_series AS (
    SELECT
        '2015-01-01'::date AS date -- Start date explicitly cast to date
    UNION ALL
    SELECT
        (date + INTERVAL '1 day')::date AS date -- Ensure recursive part also explicitly casts to date
    FROM date_series
    WHERE
        date < '2030-12-31'::date -- End date explicitly cast to date
)

SELECT
    date,
    TO_CHAR(date, 'YYYY-MM') AS year_month, -- Format YYYY-MM
    EXTRACT(YEAR FROM date) AS calendar_year, -- Extract the year
    TO_CHAR(date, 'Month') AS month_long, -- Full month name (e.g., January, February...)
    TO_CHAR(date, 'Mon') AS month_short, -- Abbreviated month name (e.g., Jan, Feb...)
    EXTRACT(MONTH FROM date) AS month_number, -- Extract the month number
    (EXTRACT(DAY FROM date)::int - 1) / 7 + 1 AS week_number -- Calculate the week number
FROM
    date_series
