{% macro stage_bank_transactions(source_name, bank_name, account_label) %}
WITH source_data AS (
  SELECT *
  FROM {{ source('personalfinance_dagster', source_name) }}
)
SELECT
  CAST(primary_key AS TEXT) AS primary_key,
  CAST(receipt AS TEXT) AS receipt,
  CAST(location AS TEXT) AS location,
  CAST(description_date AS TEXT) AS description_date,
  CAST(card_no AS TEXT) AS card_no,
  CAST(sender AS TEXT) AS sender,
  CAST(recipient AS TEXT) AS recipient,
  CAST(transaction_amount AS DOUBLE PRECISION) AS transaction_amount,
  CAST(line_number AS BIGINT) AS line_number,
  COALESCE(CAST(account_name AS TEXT), '{{ bank_name }}_{{ account_label }}') AS account_name,
  CAST(transaction_date AS DATE) AS transaction_date,
  CAST(memo AS TEXT) AS memo,
  CAST(transaction_description AS TEXT) AS transaction_description,
  CAST(transaction_type AS TEXT) AS transaction_type,
  CAST(etl_date AS DATE) AS etl_date,
  CAST(etl_time AS TIME) AS etl_time
FROM source_data
{% endmacro %}
