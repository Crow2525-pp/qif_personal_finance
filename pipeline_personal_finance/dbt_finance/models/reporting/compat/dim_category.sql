{{ config(materialized='view') }}

SELECT
  category_key AS origin_key,
  category,
  subcategory,
  store
FROM {{ ref('dim_categories') }}
