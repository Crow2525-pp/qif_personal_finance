{% set sql %}
  SELECT
    DISTINCT lower(origin_key) AS origin_key
  FROM {{ ref('dim_account') }}
  WHERE origin_key IS NOT NULL
{% endset %}

{% set results = run_query(sql) %}
{% if execute %}
  {% set accounts = results.columns[0].values() %}
{% endif %}

WITH

  /** grab the current month’s balances **/
  current_balance AS (
    SELECT *
    FROM {{ ref("viz_balance_by_year_month") }}
  ),

  /** compute what “year_month” would be one month later **/
  previous_balance AS (
    SELECT
      year_month,
      to_char(
        to_date(year_month||'-01', 'YYYY-MM-DD')
        + INTERVAL '1 month'
      , 'YYYY-MM'
      ) AS next_year_month,
      {% for account in accounts %}
        "{{ account }}"
        {% if not loop.last %}, {% endif %}
      {% endfor %}
    FROM {{ ref("viz_balance_by_year_month") }}
  ),

  /** do the month-over-month diffs **/
  monthly_differences AS (
    SELECT
      cb.year_month,
      {% for account in accounts %}
        cb."{{ account }}"
          - coalesce(pb."{{ account }}", 0)
        AS "{{ account }}_MoM"
        {% if not loop.last %}, {% endif %}
      {% endfor %}
    FROM current_balance AS cb
    LEFT JOIN previous_balance AS pb
      ON cb.year_month = pb.next_year_month
  ),

  final AS (
    SELECT *
    FROM monthly_differences
  )

SELECT * FROM final
ORDER BY year_month ASC
