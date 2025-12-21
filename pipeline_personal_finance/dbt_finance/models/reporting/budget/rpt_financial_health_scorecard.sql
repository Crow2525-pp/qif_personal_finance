{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['assessment_month'], 'unique': true}
    ]
  )
}}

-- Comprehensive financial health scorecard that combines multiple metrics
-- into an overall assessment with specific scores for different dimensions

WITH latest_periods AS (
  SELECT MAX(budget_year_month) AS latest_month
  FROM {{ ref('rpt_monthly_budget_summary') }}
  WHERE budget_year_month < TO_CHAR(CURRENT_DATE, 'YYYY-MM')
),

monthly_budget AS (
  SELECT
    budget_year_month,
    total_income,
    total_expenses,
    net_cash_flow,
    savings_rate_percent,
    expense_ratio_percent
  FROM {{ ref('rpt_monthly_budget_summary') }}
  CROSS JOIN latest_periods
  WHERE budget_year_month = latest_periods.latest_month
),

savings_metrics AS (
  SELECT
    budget_year_month,
    total_savings_rate_percent,
    liquid_savings_rate_percent,
    savings_health_score
  FROM {{ ref('rpt_savings_analysis') }}
  CROSS JOIN latest_periods
  WHERE budget_year_month = latest_periods.latest_month
),

net_worth_metrics AS (
  SELECT
    budget_year_month,
    net_worth,
    total_assets,
    total_liabilities,
    liquid_assets,
    net_worth_health_score,
    debt_to_asset_ratio
  FROM {{ ref('rpt_household_net_worth') }}
  CROSS JOIN latest_periods
  WHERE budget_year_month = latest_periods.latest_month
),

cash_flow_metrics AS (
  SELECT
    budget_year_month,
    cash_flow_efficiency_score,
    cash_flow_status
  FROM {{ ref('rpt_cash_flow_analysis') }}
  CROSS JOIN latest_periods
  WHERE budget_year_month = latest_periods.latest_month
),

-- Calculate emergency fund coverage
emergency_fund AS (
  SELECT
    nw.budget_year_month,
    nw.liquid_assets,
    mb.total_expenses,
    -- Months of expenses covered by liquid assets
    CASE
      WHEN mb.total_expenses > 0 THEN nw.liquid_assets / mb.total_expenses
      ELSE 0
    END AS months_expenses_covered,

    -- Emergency fund health score (0-100)
    CASE
      WHEN mb.total_expenses <= 0 THEN 50  -- Neutral if no expenses
      WHEN (nw.liquid_assets / mb.total_expenses) >= 12 THEN 100
      WHEN (nw.liquid_assets / mb.total_expenses) >= 6 THEN 85
      WHEN (nw.liquid_assets / mb.total_expenses) >= 3 THEN 70
      WHEN (nw.liquid_assets / mb.total_expenses) >= 1 THEN 50
      ELSE 25
    END AS emergency_fund_score
  FROM net_worth_metrics nw
  JOIN monthly_budget mb USING (budget_year_month)
),

-- Income stability score based on variance
income_stability AS (
  SELECT
    -- Look at last 6 months of income data
    STDDEV(total_income) AS income_stddev,
    AVG(total_income) AS avg_income,
    -- Coefficient of variation (lower is more stable)
    CASE
      WHEN AVG(total_income) > 0 THEN STDDEV(total_income) / AVG(total_income)
      ELSE 1
    END AS income_cv,

    -- Income stability score (0-100, higher is more stable)
    CASE
      WHEN AVG(total_income) <= 0 THEN 0
      WHEN (STDDEV(total_income) / AVG(total_income)) < 0.05 THEN 100
      WHEN (STDDEV(total_income) / AVG(total_income)) < 0.10 THEN 85
      WHEN (STDDEV(total_income) / AVG(total_income)) < 0.20 THEN 70
      WHEN (STDDEV(total_income) / AVG(total_income)) < 0.30 THEN 50
      ELSE 30
    END AS income_stability_score

  FROM {{ ref('rpt_monthly_budget_summary') }}
  WHERE to_date(budget_year_month || '-01', 'YYYY-MM-DD')
        >= (SELECT to_date(latest_month || '-01', 'YYYY-MM-DD') - INTERVAL '6 months' FROM latest_periods)
    AND to_date(budget_year_month || '-01', 'YYYY-MM-DD')
        < (SELECT to_date(latest_month || '-01', 'YYYY-MM-DD') FROM latest_periods)
),

-- Debt management score
debt_management AS (
  SELECT
    nw.budget_year_month,
    nw.total_liabilities,
    mb.total_income,

    -- Debt to income ratio
    CASE
      WHEN mb.total_income > 0 THEN ABS(nw.total_liabilities) / mb.total_income
      ELSE 0
    END AS debt_to_income_ratio,

    -- Debt management score (0-100)
    CASE
      WHEN nw.total_liabilities >= 0 THEN 100  -- No debt
      WHEN mb.total_income <= 0 THEN 20  -- No income to service debt
      WHEN (ABS(nw.total_liabilities) / mb.total_income) < 2 THEN 90
      WHEN (ABS(nw.total_liabilities) / mb.total_income) < 3 THEN 75
      WHEN (ABS(nw.total_liabilities) / mb.total_income) < 4 THEN 60
      WHEN (ABS(nw.total_liabilities) / mb.total_income) < 5 THEN 45
      ELSE 25
    END AS debt_management_score

  FROM net_worth_metrics nw
  JOIN monthly_budget mb USING (budget_year_month)
),

-- Spending control score based on expense trends
spending_control AS (
  SELECT
    -- Compare last month to 3-month average
    curr.total_expenses AS current_month_expenses,
    AVG(hist.total_expenses) AS avg_3month_expenses,

    CASE
      WHEN AVG(hist.total_expenses) = 0 THEN 0
      ELSE (curr.total_expenses - AVG(hist.total_expenses)) / AVG(hist.total_expenses)
    END AS expense_variance_pct,

    -- Spending control score (0-100)
    CASE
      WHEN AVG(hist.total_expenses) <= 0 THEN 50
      -- If spending decreased, that's good
      WHEN curr.total_expenses < AVG(hist.total_expenses) THEN 100
      -- If increased by less than 5%, still good
      WHEN ((curr.total_expenses - AVG(hist.total_expenses)) / AVG(hist.total_expenses)) < 0.05 THEN 85
      WHEN ((curr.total_expenses - AVG(hist.total_expenses)) / AVG(hist.total_expenses)) < 0.10 THEN 70
      WHEN ((curr.total_expenses - AVG(hist.total_expenses)) / AVG(hist.total_expenses)) < 0.20 THEN 50
      ELSE 30
    END AS spending_control_score

  FROM latest_periods lp
  CROSS JOIN {{ ref('rpt_monthly_budget_summary') }} curr
  LEFT JOIN {{ ref('rpt_monthly_budget_summary') }} hist
    ON to_date(hist.budget_year_month || '-01', 'YYYY-MM-DD')
       >= to_date(curr.budget_year_month || '-01', 'YYYY-MM-DD') - INTERVAL '4 months'
   AND to_date(hist.budget_year_month || '-01', 'YYYY-MM-DD')
       < to_date(curr.budget_year_month || '-01', 'YYYY-MM-DD')
  WHERE curr.budget_year_month = lp.latest_month
  GROUP BY curr.budget_year_month, curr.total_expenses
),

scorecard AS (
  SELECT
    mb.budget_year_month AS assessment_month,

    -- Individual dimension scores (0-100 scale)
    ROUND(COALESCE(sm.savings_health_score, 50), 1) AS savings_score,
    ROUND(COALESCE(nw.net_worth_health_score, 50), 1) AS net_worth_score,
    ROUND(COALESCE(cf.cash_flow_efficiency_score, 50), 1) AS cash_flow_score,
    ROUND(COALESCE(ef.emergency_fund_score, 50), 1) AS emergency_fund_score,
    ROUND(COALESCE(is_calc.income_stability_score, 50), 1) AS income_stability_score,
    ROUND(COALESCE(dm.debt_management_score, 50), 1) AS debt_management_score,
    ROUND(COALESCE(sc.spending_control_score, 50), 1) AS spending_control_score,

    -- Overall financial health score (weighted average)
    ROUND(
      (COALESCE(sm.savings_health_score, 50) * 0.20 +
       COALESCE(nw.net_worth_health_score, 50) * 0.20 +
       COALESCE(cf.cash_flow_efficiency_score, 50) * 0.15 +
       COALESCE(ef.emergency_fund_score, 50) * 0.15 +
       COALESCE(is_calc.income_stability_score, 50) * 0.10 +
       COALESCE(dm.debt_management_score, 50) * 0.10 +
       COALESCE(sc.spending_control_score, 50) * 0.10),
      1
    ) AS overall_financial_health_score,

    -- Supporting metrics
    ROUND(mb.total_income, 0) AS monthly_income,
    ROUND(mb.total_expenses, 0) AS monthly_expenses,
    ROUND(mb.net_cash_flow, 0) AS monthly_net_cash_flow,
    ROUND(sm.total_savings_rate_percent * 100, 1) AS savings_rate_pct,
    ROUND(nw.net_worth, 0) AS net_worth,
    ROUND(nw.liquid_assets, 0) AS liquid_assets,
    ROUND(ef.months_expenses_covered, 1) AS emergency_fund_months_coverage,
    ROUND(dm.debt_to_income_ratio, 2) AS debt_to_income_ratio,
    ROUND(nw.debt_to_asset_ratio * 100, 1) AS debt_to_asset_ratio_pct,
    cf.cash_flow_status,

    CURRENT_TIMESTAMP AS report_generated_at

  FROM monthly_budget mb
  LEFT JOIN savings_metrics sm USING (budget_year_month)
  LEFT JOIN net_worth_metrics nw USING (budget_year_month)
  LEFT JOIN cash_flow_metrics cf USING (budget_year_month)
  LEFT JOIN emergency_fund ef USING (budget_year_month)
  CROSS JOIN income_stability is_calc
  LEFT JOIN debt_management dm USING (budget_year_month)
  CROSS JOIN spending_control sc
),

final_scorecard AS (
  SELECT
    *,

    -- Overall financial health rating
    CASE
      WHEN overall_financial_health_score >= 85 THEN 'Excellent'
      WHEN overall_financial_health_score >= 70 THEN 'Very Good'
      WHEN overall_financial_health_score >= 60 THEN 'Good'
      WHEN overall_financial_health_score >= 50 THEN 'Fair'
      WHEN overall_financial_health_score >= 40 THEN 'Needs Improvement'
      ELSE 'Poor'
    END AS overall_health_rating,

    -- Identify strengths (scores >= 80)
    ARRAY_REMOVE(ARRAY[
      CASE WHEN savings_score >= 80 THEN 'Savings' END,
      CASE WHEN net_worth_score >= 80 THEN 'Net Worth' END,
      CASE WHEN cash_flow_score >= 80 THEN 'Cash Flow' END,
      CASE WHEN emergency_fund_score >= 80 THEN 'Emergency Fund' END,
      CASE WHEN income_stability_score >= 80 THEN 'Income Stability' END,
      CASE WHEN debt_management_score >= 80 THEN 'Debt Management' END,
      CASE WHEN spending_control_score >= 80 THEN 'Spending Control' END
    ], NULL) AS financial_strengths,

    -- Identify areas needing attention (scores < 60)
    ARRAY_REMOVE(ARRAY[
      CASE WHEN savings_score < 60 THEN 'Savings' END,
      CASE WHEN net_worth_score < 60 THEN 'Net Worth' END,
      CASE WHEN cash_flow_score < 60 THEN 'Cash Flow' END,
      CASE WHEN emergency_fund_score < 60 THEN 'Emergency Fund' END,
      CASE WHEN income_stability_score < 60 THEN 'Income Stability' END,
      CASE WHEN debt_management_score < 60 THEN 'Debt Management' END,
      CASE WHEN spending_control_score < 60 THEN 'Spending Control' END
    ], NULL) AS areas_needing_attention,

    -- Top priority for improvement (lowest score)
    CASE
      WHEN savings_score = LEAST(savings_score, net_worth_score, cash_flow_score,
                                  emergency_fund_score, income_stability_score,
                                  debt_management_score, spending_control_score)
           THEN 'Focus on Savings'
      WHEN net_worth_score = LEAST(savings_score, net_worth_score, cash_flow_score,
                                    emergency_fund_score, income_stability_score,
                                    debt_management_score, spending_control_score)
           THEN 'Focus on Net Worth Growth'
      WHEN cash_flow_score = LEAST(savings_score, net_worth_score, cash_flow_score,
                                    emergency_fund_score, income_stability_score,
                                    debt_management_score, spending_control_score)
           THEN 'Focus on Cash Flow Management'
      WHEN emergency_fund_score = LEAST(savings_score, net_worth_score, cash_flow_score,
                                         emergency_fund_score, income_stability_score,
                                         debt_management_score, spending_control_score)
           THEN 'Build Emergency Fund'
      WHEN income_stability_score = LEAST(savings_score, net_worth_score, cash_flow_score,
                                           emergency_fund_score, income_stability_score,
                                           debt_management_score, spending_control_score)
           THEN 'Stabilize Income'
      WHEN debt_management_score = LEAST(savings_score, net_worth_score, cash_flow_score,
                                          emergency_fund_score, income_stability_score,
                                          debt_management_score, spending_control_score)
           THEN 'Reduce Debt'
      ELSE 'Control Spending'
    END AS top_priority_for_improvement

  FROM scorecard
)

SELECT * FROM final_scorecard
