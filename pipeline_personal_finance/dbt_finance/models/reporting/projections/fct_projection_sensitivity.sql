{{ config(materialized='table') }}

-- Financial Projections with Sensitivity Analysis
-- Supports income/expense delta adjustments for scenario testing
-- Pre-computes deltas for common sensitivity percentages to support Grafana visualization

WITH base_projections AS (
    SELECT
        fp.*,

        -- Baseline deltas (for reference and calibration)
        (total_projected_income * 0.1) as income_plus_10pct_delta,
        (total_projected_income * -0.1) as income_minus_10pct_delta,
        (projected_monthly_expenses * 0.1) as expense_plus_10pct_delta,
        (projected_monthly_expenses * -0.1) as expense_minus_10pct_delta

    FROM {{ ref('fct_financial_projections') }} fp
),

projection_gaps AS (
    SELECT
        bp.*,

        -- Projected vs Historical Comparison (same month, previous year)
        COALESCE(hm.actual_income, 0) as prev_year_actual_income,
        COALESCE(hm.actual_expenses, 0) as prev_year_actual_expenses,
        COALESCE(hm.actual_net_flow, 0) as prev_year_actual_net_flow,

        -- Gap Analysis (Projected - Actual)
        bp.total_projected_income - COALESCE(hm.actual_income, 0) as income_gap,
        bp.projected_monthly_expenses - COALESCE(hm.actual_expenses, 0) as expense_gap,
        (bp.total_projected_income - bp.projected_monthly_expenses) - COALESCE(hm.actual_net_flow, 0) as net_flow_gap,

        -- Gap as percentage (for understanding projection accuracy)
        CASE
            WHEN COALESCE(hm.actual_income, 0) > 0 THEN
                (bp.total_projected_income - COALESCE(hm.actual_income, 0)) / COALESCE(hm.actual_income, 0)
            ELSE NULL
        END as income_gap_pct,

        CASE
            WHEN COALESCE(hm.actual_expenses, 0) > 0 THEN
                (bp.projected_monthly_expenses - COALESCE(hm.actual_expenses, 0)) / COALESCE(hm.actual_expenses, 0)
            ELSE NULL
        END as expense_gap_pct,

        -- Confidence bounds (upper/lower bounds for expense forecasts)
        bp.upper_expense_bound,
        bp.lower_expense_bound

    FROM base_projections bp
    LEFT JOIN (
        SELECT
            DATE_TRUNC('month', transaction_date) as month,
            SUM(CASE WHEN transaction_amount > 0 THEN transaction_amount ELSE 0 END) as actual_income,
            SUM(CASE WHEN transaction_amount < 0 THEN ABS(transaction_amount) ELSE 0 END) as actual_expenses,
            SUM(transaction_amount) as actual_net_flow
        FROM {{ ref('fct_transactions') }}
        WHERE transaction_date >= DATE_TRUNC('month', CURRENT_DATE - INTERVAL '24 months')
        GROUP BY DATE_TRUNC('month', transaction_date)
    ) hm ON DATE_TRUNC('month', bp.projection_date - INTERVAL '12 months') = hm.month
)

SELECT
    *,

    -- Sensitivity bands (for what-if analysis)
    total_projected_income * 0.9 as conservative_income,
    total_projected_income * 1.1 as optimistic_income,
    projected_monthly_expenses * 0.9 as conservative_expenses,
    projected_monthly_expenses * 1.1 as optimistic_expenses,

    -- Adjusted net flows based on sensitivity ranges
    (total_projected_income * 0.9) - (projected_monthly_expenses * 1.1) as worst_case_net_flow,
    (total_projected_income * 1.1) - (projected_monthly_expenses * 0.9) as best_case_net_flow

FROM projection_gaps
ORDER BY scenario, projection_month
