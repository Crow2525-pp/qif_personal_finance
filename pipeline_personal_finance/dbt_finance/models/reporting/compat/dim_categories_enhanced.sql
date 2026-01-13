{{ config(materialized='view') }}

SELECT * FROM {{ ref('dim_categories') }}
