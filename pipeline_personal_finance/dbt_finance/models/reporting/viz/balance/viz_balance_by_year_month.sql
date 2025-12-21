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

  /**​ Grab only the last snapshot of each month for each account **/
  monthly_snapshot AS (
    SELECT
      date_trunc('month', daily.period_date)::date    AS month_start_date,
      daily.account_foreign_key                       AS account_key,
      daily.end_of_day_balance                        AS balance
    FROM (
      SELECT
        period_date,
        account_foreign_key,
        end_of_day_balance,
        row_number() OVER (
          PARTITION BY account_foreign_key,
                       date_trunc('month', period_date)
          ORDER BY period_date DESC
        ) AS rn
      FROM {{ ref('rpt_periodic_snapshot_yyyymm_balance') }} AS daily
    ) AS daily
    WHERE rn = 1
  ),

  /**​ Pivot that into one column per account **/
  pivot_balances AS (
    SELECT
      MIN(month_start_date)::date                 AS period_date,
      to_char(month_start_date, 'YYYY-MM')        AS year_month,
      {% for account in accounts %}
        max(
          CASE
            WHEN upper(account_key) = upper('{{ account }}')
            THEN balance
            ELSE NULL
          END
        )                                        AS "{{ account }}"
        {% if not loop.last %}, {% endif %}
      {% endfor %}
    FROM monthly_snapshot
    GROUP BY 2
    ORDER BY 1
  ),

  /**​ Filter out months where every balance is zero **/
  final AS (
    SELECT
      period_date,
      year_month,
      {% for account in accounts %}
        "{{ account }}"
        {% if not loop.last %}, {% endif %}
      {% endfor %}
    FROM pivot_balances
    WHERE
      {% for account in accounts %}
        coalesce("{{ account }}", 0) != 0
        {% if not loop.last %} OR {% endif %}
      {% endfor %}
  )

SELECT * FROM final
ORDER BY period_date
