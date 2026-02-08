{{ config(materialized='view') }}

{% set rel = ref('rpt_outflows_insights_dashboard') %}
{% set cols = adapter.get_columns_in_relation(rel) %}
{% set col_names = cols | map(attribute='name') | map('lower') | list %}

SELECT
  src.*
  {% if 'uncategorized_amount' not in col_names and 'uncategorized' in col_names %}
  , src.uncategorized AS uncategorized_amount
  {% endif %}
  {% if 'uncategorized' not in col_names and 'uncategorized_amount' in col_names %}
  , src.uncategorized_amount AS uncategorized
  {% endif %}
FROM {{ rel }} src
