{%
  set unique_period = target.type != 'duckdb'
%}
{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['period_month'], 'unique': unique_period},
      {'columns': ['account_name'], 'unique': false}
    ]
  )
}}

-- Tracks mortgage and debt reduction progress over time,
-- calculates principal vs interest, and projects payoff dates

WITH liability_accounts AS (
  SELECT
    account_key,
    account_name,
    account_type,
    is_mortgage
  FROM {{ ref('dim_accounts') }}
  WHERE is_liability = TRUE
),

monthly_balances AS (
  SELECT
    fdb.account_key,
    da.account_name,
    da.is_mortgage,
    DATE_TRUNC('month', fdb.balance_date)::date AS period_month,
    -- End of month balance (negative = owed)
    FIRST_VALUE(fdb.daily_balance) OVER (
      PARTITION BY fdb.account_key, DATE_TRUNC('month', fdb.balance_date)
      ORDER BY fdb.balance_date DESC
    ) AS eom_balance
  FROM {{ ref('fct_daily_balances') }} fdb
  JOIN liability_accounts da
    ON fdb.account_key = da.account_key
),

distinct_monthly_balances AS (
  SELECT DISTINCT
    account_key,
    account_name,
    is_mortgage,
    period_month,
    eom_balance
  FROM monthly_balances
),

monthly_transactions AS (
  SELECT
    ft.account_key,
    da.account_name,
    da.is_mortgage,
    DATE_TRUNC('month', ft.transaction_date)::date AS period_month,

    -- Total payments made (negative amounts reduce the debt)
    SUM(CASE
      WHEN ft.transaction_amount < 0 THEN ABS(ft.transaction_amount)
      ELSE 0
    END) AS total_payments,

    -- Interest charges (positive amounts increase debt)
    SUM(CASE
      WHEN ft.transaction_amount > 0
           AND (ft.transaction_description ILIKE '%interest%'
                OR ft.transaction_memo ILIKE '%interest%'
                OR ft.transaction_type ILIKE '%interest%')
      THEN ABS(ft.transaction_amount)
      ELSE 0
    END) AS interest_charged,

    -- Fees (positive amounts that aren't interest)
    SUM(CASE
      WHEN ft.transaction_amount > 0
           AND NOT (ft.transaction_description ILIKE '%interest%'
                    OR ft.transaction_memo ILIKE '%interest%'
                    OR ft.transaction_type ILIKE '%interest%')
      THEN ABS(ft.transaction_amount)
      ELSE 0
    END) AS fees_charged,

    COUNT(CASE WHEN ft.transaction_amount < 0 THEN 1 END) AS payment_count

  FROM {{ ref('fct_transactions') }} ft
  JOIN liability_accounts da
    ON ft.account_key = da.account_key
  WHERE NOT COALESCE(ft.is_internal_transfer, FALSE)
  GROUP BY ft.account_key, da.account_name, da.is_mortgage, DATE_TRUNC('month', ft.transaction_date)::date
),

combined_metrics AS (
  SELECT
    COALESCE(b.period_month, t.period_month) AS period_month,
    COALESCE(b.account_key, t.account_key) AS account_key,
    COALESCE(b.account_name, t.account_name) AS account_name,
    COALESCE(b.is_mortgage, t.is_mortgage) AS is_mortgage,

    ABS(COALESCE(b.eom_balance, 0)) AS debt_balance,
    COALESCE(t.total_payments, 0) AS total_payments,
    COALESCE(t.interest_charged, 0) AS interest_charged,
    COALESCE(t.fees_charged, 0) AS fees_charged,
    COALESCE(t.payment_count, 0) AS payment_count

  FROM distinct_monthly_balances b
  FULL OUTER JOIN monthly_transactions t
    ON b.account_key = t.account_key
    AND b.period_month = t.period_month
),

debt_metrics_base AS (
  SELECT
    *,
    -- Principal reduction = payments - interest - fees
    (total_payments - interest_charged - fees_charged) AS principal_paid,

    -- Month-over-month debt reduction
    debt_balance - LAG(debt_balance) OVER (
      PARTITION BY account_key
      ORDER BY period_month
    ) AS mom_debt_change,

    -- Previous month balance for calculations
    LAG(debt_balance) OVER (
      PARTITION BY account_key
      ORDER BY period_month
    ) AS prev_month_balance,

    -- Calculate effective interest rate
    CASE
      WHEN LAG(debt_balance) OVER (PARTITION BY account_key ORDER BY period_month) > 0
      THEN (interest_charged / LAG(debt_balance) OVER (PARTITION BY account_key ORDER BY period_month)) * 12
      ELSE 0
    END AS estimated_annual_interest_rate

  FROM combined_metrics
),

debt_metrics AS (
  SELECT
    *,
    -- Cumulative metrics
    SUM(total_payments) OVER (
      PARTITION BY account_key
      ORDER BY period_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_payments,

    SUM(interest_charged) OVER (
      PARTITION BY account_key
      ORDER BY period_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_interest_paid,

    SUM(principal_paid) OVER (
      PARTITION BY account_key
      ORDER BY period_month
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS cumulative_principal_paid

  FROM debt_metrics_base
),

debt_trends AS (
  SELECT
    *,
    -- 3-month rolling averages
    AVG(total_payments) OVER (
      PARTITION BY account_key
      ORDER BY period_month
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3m_avg_payment,

    AVG(principal_paid) OVER (
      PARTITION BY account_key
      ORDER BY period_month
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3m_avg_principal,

    AVG(interest_charged) OVER (
      PARTITION BY account_key
      ORDER BY period_month
      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS rolling_3m_avg_interest,

    -- 12-month rolling averages
    AVG(total_payments) OVER (
      PARTITION BY account_key
      ORDER BY period_month
      ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
    ) AS rolling_12m_avg_payment,

    AVG(principal_paid) OVER (
      PARTITION BY account_key
      ORDER BY period_month
      ROWS BETWEEN 11 PRECEDING AND CURRENT ROW
    ) AS rolling_12m_avg_principal

  FROM debt_metrics
),

payoff_projections AS (
  SELECT
    *,
    -- Estimated months to payoff at current rate
    CASE
      WHEN rolling_3m_avg_principal > 0 THEN
        CEIL(debt_balance / rolling_3m_avg_principal)
      ELSE NULL
    END AS estimated_months_to_payoff,

    -- Projected payoff date based on 3-month average principal
    CASE
      WHEN rolling_3m_avg_principal > 0 THEN
        period_month + (CEIL(debt_balance / rolling_3m_avg_principal) || ' months')::interval
      ELSE NULL
    END AS projected_payoff_date,

    -- Interest to principal ratio
    CASE
      WHEN principal_paid > 0 THEN interest_charged / principal_paid
      ELSE 0
    END AS interest_to_principal_ratio,

    -- Payment efficiency score (higher is better, 100 = all principal, 0 = all interest)
    -- Clamped to 0-100 to handle edge cases (negative principal or principal > total)
    CASE
      WHEN total_payments > 0 THEN GREATEST(0, LEAST(100, (principal_paid / total_payments) * 100))
      ELSE 0
    END AS payment_efficiency_score

  FROM debt_trends
),

final_report AS (
  SELECT
    period_month,
    account_name,
    is_mortgage,

    -- Balance metrics
    ROUND(debt_balance, 2) AS outstanding_debt_balance,
    ROUND(prev_month_balance, 2) AS previous_month_balance,
    ROUND(mom_debt_change, 2) AS month_over_month_reduction,

    -- Payment breakdown
    ROUND(total_payments, 2) AS total_monthly_payment,
    ROUND(principal_paid, 2) AS principal_reduction,
    ROUND(interest_charged, 2) AS interest_paid,
    ROUND(fees_charged, 2) AS fees_paid,
    payment_count,

    -- Cumulative totals
    ROUND(cumulative_payments, 2) AS lifetime_total_payments,
    ROUND(cumulative_principal_paid, 2) AS lifetime_principal_paid,
    ROUND(cumulative_interest_paid, 2) AS lifetime_interest_paid,

    -- Rates and ratios
    ROUND(estimated_annual_interest_rate * 100, 2) AS estimated_interest_rate_pct,
    ROUND(interest_to_principal_ratio, 3) AS interest_to_principal_ratio,
    ROUND(payment_efficiency_score, 1) AS payment_efficiency_score,

    -- Averages
    ROUND(rolling_3m_avg_payment, 2) AS avg_3month_payment,
    ROUND(rolling_3m_avg_principal, 2) AS avg_3month_principal,
    ROUND(rolling_3m_avg_interest, 2) AS avg_3month_interest,
    ROUND(rolling_12m_avg_payment, 2) AS avg_12month_payment,
    ROUND(rolling_12m_avg_principal, 2) AS avg_12month_principal,

    -- Projections
    estimated_months_to_payoff,
    projected_payoff_date,

    -- Progress indicators
    CASE
      WHEN mom_debt_change < 0 THEN 'Debt Increasing'
      WHEN mom_debt_change = 0 THEN 'No Change'
      WHEN mom_debt_change > 0 AND mom_debt_change < rolling_3m_avg_principal THEN 'Below Average Progress'
      WHEN mom_debt_change >= rolling_3m_avg_principal THEN 'On Track or Better'
      ELSE 'Unknown'
    END AS debt_reduction_status,

    CASE
      WHEN payment_efficiency_score >= 80 THEN 'Excellent (>80% to principal)'
      WHEN payment_efficiency_score >= 60 THEN 'Good (60-80% to principal)'
      WHEN payment_efficiency_score >= 40 THEN 'Fair (40-60% to principal)'
      ELSE 'Poor (<40% to principal)'
    END AS payment_efficiency_rating,

    CURRENT_TIMESTAMP AS report_generated_at

  FROM payoff_projections
  WHERE period_month < DATE_TRUNC('month', CURRENT_DATE)  -- Exclude incomplete current month
)

SELECT * FROM final_report
ORDER BY period_month DESC, account_name
