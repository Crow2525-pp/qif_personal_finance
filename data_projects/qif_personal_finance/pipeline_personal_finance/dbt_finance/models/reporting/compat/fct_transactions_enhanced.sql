{{ config(materialized='view') }}

SELECT * FROM {{ ref('fct_transactions') }}
