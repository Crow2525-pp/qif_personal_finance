{{ config(materialized='table') }}

WITH historical_baseline AS (
    SELECT
        AVG(total_expenses) as avg_monthly_expenses,
        STDDEV(total_expenses) as stddev_monthly_expenses,
        MAX(income_growth_rate) as historical_income_growth,
        MAX(expense_growth_rate) as historical_expense_growth
    FROM {{ ref('base_historical_trends') }}
    WHERE month >= DATE_TRUNC('month', CURRENT_DATE - INTERVAL '12 months')
),

expense_projections AS (
    SELECT
        pp.scenario,
        pp.projection_date,
        pp.projection_month,
        pp.projected_monthly_income,
        pp.monthly_bonus_allocation,
        pp.monthly_tax_refund_allocation,
        pp.work_factor,

        -- Total projected income
        pp.projected_monthly_income +
        pp.monthly_bonus_allocation +
        pp.monthly_tax_refund_allocation as total_projected_income,

        -- Project expenses based on historical average with growth
        hb.avg_monthly_expenses *
        POWER(1 + (pp.expense_growth_rate / 12), pp.projection_month) as projected_monthly_expenses,

        -- Conservative and optimistic scenarios
        hb.avg_monthly_expenses *
        POWER(1 + (pp.expense_growth_rate / 12), pp.projection_month) * 1.1 as conservative_expenses,

        hb.avg_monthly_expenses *
        POWER(1 + (pp.expense_growth_rate / 12), pp.projection_month) * 0.9 as optimistic_expenses,

        hb.avg_monthly_expenses,
        hb.stddev_monthly_expenses

    FROM {{ ref('projection_parameters') }} pp
    CROSS JOIN historical_baseline hb
),

final_projections AS (
    SELECT
        scenario,
        projection_date,
        projection_month,
        work_factor,

        -- Income projections
        projected_monthly_income,
        monthly_bonus_allocation,
        monthly_tax_refund_allocation,
        total_projected_income,

        -- Expense projections
        projected_monthly_expenses,
        conservative_expenses,
        optimistic_expenses,

        -- Net flow projections
        total_projected_income - projected_monthly_expenses as projected_net_flow,
        total_projected_income - conservative_expenses as conservative_net_flow,
        total_projected_income - optimistic_expenses as optimistic_net_flow,

        -- Cumulative projections
        SUM(total_projected_income - projected_monthly_expenses)
            OVER (PARTITION BY scenario ORDER BY projection_month) as cumulative_net_flow,

        SUM(total_projected_income)
            OVER (PARTITION BY scenario ORDER BY projection_month) as cumulative_income,

        SUM(projected_monthly_expenses)
            OVER (PARTITION BY scenario ORDER BY projection_month) as cumulative_expenses,

        -- Year-over-year comparison (vs same month last year)
        EXTRACT(month FROM projection_date) as month_num,
        EXTRACT(year FROM projection_date) as year_num,

        avg_monthly_expenses,
        stddev_monthly_expenses

    FROM expense_projections
)

SELECT
    fp.*,

    -- Calculate savings rate
    CASE
        WHEN total_projected_income > 0 THEN
            projected_net_flow / total_projected_income
        ELSE 0
    END as projected_savings_rate,

    -- Emergency fund months (assuming 6 month target)
    CASE
        WHEN projected_monthly_expenses > 0 THEN
            cumulative_net_flow / projected_monthly_expenses
        ELSE 0
    END as emergency_fund_months,

    -- Confidence intervals
    projected_monthly_expenses + stddev_monthly_expenses as upper_expense_bound,
    projected_monthly_expenses - stddev_monthly_expenses as lower_expense_bound

FROM final_projections fp
ORDER BY scenario, projection_month