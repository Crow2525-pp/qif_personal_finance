{% set sql %}
  SELECT DISTINCT lower(account_key) AS account_key
  FROM {{ ref('dim_accounts_enhanced') }}
  WHERE account_key IS NOT NULL
{% endset %}

{% set results = run_query(sql) %}
{% if execute %}
  {% set accounts = results.columns[0].values() %}
{% else %}
  {% set accounts = [] %}
{% endif %}

WITH base AS (
    SELECT 
        to_char(transaction_date, 'YYYY-MM') AS year_month,
        account_key
    FROM {{ ref('fct_transactions_enhanced') }}
),
tx_counts AS (
    SELECT
        year_month,
        account_key,
        COUNT(*) AS tx_count
    FROM base
    GROUP BY 1, 2
)
SELECT
    year_month
    {% if accounts | length > 0 %}
      , {% for account in accounts %}
          MAX(CASE WHEN lower(account_key) = lower('{{ account }}') THEN tx_count END) AS "{{ account }}"{% if not loop.last %}, {% endif %}
        {% endfor %}
    {% else %}
      , SUM(tx_count) AS total_tx_count
    {% endif %}
FROM tx_counts
GROUP BY year_month
ORDER BY year_month
