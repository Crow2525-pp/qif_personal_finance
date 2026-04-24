{% macro stage_bank_transactions(source_name, bank_name, account_label) %}
{% set source_relation = source('personalfinance_dagster', source_name) %}
{% set column_names = adapter.get_columns_in_relation(source_relation) | map(attribute='name') | map('lower') | list %}
{% set amount_expr = 'transaction_amount' if 'transaction_amount' in column_names else ('amount' if 'amount' in column_names else 'NULL') %}
{% set date_expr = 'transaction_date' if 'transaction_date' in column_names else ('date' if 'date' in column_names else 'NULL') %}
{% set memo_expr = 'memo' if 'memo' in column_names else ('notes' if 'notes' in column_names else 'NULL') %}
{% set description_expr = 'transaction_description' if 'transaction_description' in column_names else ('description' if 'description' in column_names else ('payee' if 'payee' in column_names else memo_expr)) %}
{% set type_expr = 'transaction_type' if 'transaction_type' in column_names else ('type' if 'type' in column_names else 'NULL') %}
{% set line_number_expr = 'line_number' if 'line_number' in column_names else 'NULL' %}
{% set primary_key_expr = 'primary_key' if 'primary_key' in column_names else 'NULL' %}
{% set account_name_expr = 'account_name' if 'account_name' in column_names else (adapter.quote('AccountName') if 'accountname' in column_names else 'NULL') %}
{% set etl_date_expr = 'etl_date' if 'etl_date' in column_names else 'NULL' %}
{% set etl_time_expr = 'etl_time' if 'etl_time' in column_names else 'NULL' %}
{% set line_order_expr = 'transaction_date' if 'transaction_date' in column_names else ('date' if 'date' in column_names else '1') %}
WITH source_data AS (
  SELECT *
  FROM {{ source_relation }}
)
SELECT
  {% if primary_key_expr != 'NULL' %}
  CAST({{ primary_key_expr }} AS TEXT) AS primary_key,
  {% else %}
  md5(
    COALESCE(CAST({{ date_expr }} AS TEXT), '') || '-' ||
    COALESCE(CAST({{ amount_expr }} AS TEXT), '') || '-' ||
    COALESCE(CAST({{ memo_expr }} AS TEXT), '')
  ) AS primary_key,
  {% endif %}
  {% if 'receipt' in column_names %}
  CAST(receipt AS TEXT) AS receipt,
  {% else %}
  CAST(NULL AS TEXT) AS receipt,
  {% endif %}
  {% if 'location' in column_names %}
  CAST(location AS TEXT) AS location,
  {% else %}
  CAST(NULL AS TEXT) AS location,
  {% endif %}
  {% if 'description_date' in column_names %}
  CAST(description_date AS TEXT) AS description_date,
  {% else %}
  CAST(NULL AS TEXT) AS description_date,
  {% endif %}
  {% if 'card_no' in column_names %}
  CAST(card_no AS TEXT) AS card_no,
  {% else %}
  CAST(NULL AS TEXT) AS card_no,
  {% endif %}
  {% if 'sender' in column_names %}
  CAST(sender AS TEXT) AS sender,
  {% else %}
  CAST(NULL AS TEXT) AS sender,
  {% endif %}
  {% if 'recipient' in column_names %}
  CAST(recipient AS TEXT) AS recipient,
  {% else %}
  CAST(NULL AS TEXT) AS recipient,
  {% endif %}
  CAST({{ amount_expr }} AS DOUBLE PRECISION) AS transaction_amount,
  {% if line_number_expr != 'NULL' %}
  CAST({{ line_number_expr }} AS BIGINT) AS line_number,
  {% else %}
  CAST(ROW_NUMBER() OVER (ORDER BY {{ line_order_expr }}) AS BIGINT) AS line_number,
  {% endif %}
  {% if account_name_expr != 'NULL' %}
  COALESCE(CAST({{ account_name_expr }} AS TEXT), '{{ bank_name }}_{{ account_label }}') AS account_name,
  {% else %}
  '{{ bank_name }}_{{ account_label }}' AS account_name,
  {% endif %}
  CAST({{ date_expr }} AS DATE) AS transaction_date,
  CAST({{ memo_expr }} AS TEXT) AS memo,
  CAST({{ description_expr }} AS TEXT) AS transaction_description,
  CAST({{ type_expr }} AS TEXT) AS transaction_type,
  {% if etl_date_expr != 'NULL' %}
  CAST({{ etl_date_expr }} AS DATE) AS etl_date,
  {% else %}
  CAST(NULL AS DATE) AS etl_date,
  {% endif %}
  {% if etl_time_expr != 'NULL' %}
  CAST({{ etl_time_expr }} AS TIME) AS etl_time
  {% else %}
  CAST(NULL AS TIME) AS etl_time
  {% endif %}
FROM source_data
{% endmacro %}
