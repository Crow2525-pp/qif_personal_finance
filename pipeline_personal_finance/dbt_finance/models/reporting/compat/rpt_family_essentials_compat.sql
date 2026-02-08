{{ config(materialized='view') }}

{% set rel = ref('rpt_family_essentials') %}
{% set cols = adapter.get_columns_in_relation(rel) %}
{% set col_names = cols | map(attribute='name') | map('lower') | list %}

SELECT
  src.*
  {% if 'total_essential_expenses' not in col_names and 'total_family_essentials' in col_names %}
  , src.total_family_essentials AS total_essential_expenses
  {% endif %}
  {% if 'total_family_essentials' not in col_names and 'total_essential_expenses' in col_names %}
  , src.total_essential_expenses AS total_family_essentials
  {% endif %}
FROM {{ rel }} src
