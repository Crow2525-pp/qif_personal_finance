{{ config(materialized='table') }}

WITH historical_monthly AS (
    SELECT
        DATE_TRUNC('month', date) as month,
        SUM(CASE WHEN amount > 0 THEN amount ELSE 0 END) as actual_income,
        SUM(CASE WHEN amount < 0 THEN ABS(amount) ELSE 0 END) as actual_expenses,
        SUM(amount) as actual_net_flow
    FROM {{ ref('fct_transactions') }}
    WHERE date >= DATE_TRUNC('month', CURRENT_DATE - INTERVAL '24 months')
    GROUP BY DATE_TRUNC('month', date)
),

projection_data AS (
    SELECT
        scenario,
        projection_date as month,
        total_projected_income as projected_income,
        projected_monthly_expenses as projected_expenses,
        projected_net_flow as projected_net_flow,
        cumulative_net_flow,
        projected_savings_rate,
        work_factor
    FROM {{ ref('fct_financial_projections') }}
),

yoy_comparison AS (
    SELECT
        pd.scenario,
        pd.month,
        pd.work_factor,

        -- Current projections
        pd.projected_income,
        pd.projected_expenses,
        pd.projected_net_flow,
        pd.cumulative_net_flow,
        pd.projected_savings_rate,

        -- Historical actuals (same month, previous year)
        hm.actual_income as prev_year_actual_income,
        hm.actual_expenses as prev_year_actual_expenses,
        hm.actual_net_flow as prev_year_actual_net_flow,

        -- YoY growth calculations
        CASE
            WHEN hm.actual_income > 0 THEN
                (pd.projected_income - hm.actual_income) / hm.actual_income
            ELSE NULL
        END as yoy_income_growth,

        CASE
            WHEN hm.actual_expenses > 0 THEN
                (pd.projected_expenses - hm.actual_expenses) / hm.actual_expenses
            ELSE NULL
        END as yoy_expense_growth,

        -- Quarter information for grouping
        EXTRACT(quarter FROM pd.month) as quarter,
        EXTRACT(year FROM pd.month) as year

    FROM projection_data pd
    LEFT JOIN historical_monthly hm
        ON DATE_TRUNC('month', pd.month - INTERVAL '12 months') = hm.month
),

quarterly_summary AS (
    SELECT
        scenario,
        year,
        quarter,
        work_factor,

        -- Quarterly aggregates
        SUM(projected_income) as quarterly_projected_income,
        SUM(projected_expenses) as quarterly_projected_expenses,
        SUM(projected_net_flow) as quarterly_projected_net_flow,

        SUM(prev_year_actual_income) as quarterly_prev_year_income,
        SUM(prev_year_actual_expenses) as quarterly_prev_year_expenses,
        SUM(prev_year_actual_net_flow) as quarterly_prev_year_net_flow,

        AVG(yoy_income_growth) as avg_quarterly_income_growth,
        AVG(yoy_expense_growth) as avg_quarterly_expense_growth,
        AVG(projected_savings_rate) as avg_quarterly_savings_rate

    FROM yoy_comparison
    GROUP BY scenario, year, quarter, work_factor
)

SELECT
    -- Monthly data
    yc.*,

    -- Add quarterly context
    qs.quarterly_projected_income,
    qs.quarterly_projected_expenses,
    qs.quarterly_projected_net_flow,
    qs.avg_quarterly_savings_rate,

    -- Scenario comparison (full-time vs part-time difference)
    LAG(yc.projected_income) OVER (
        PARTITION BY yc.month ORDER BY yc.scenario
    ) as other_scenario_income,

    LAG(yc.projected_net_flow) OVER (
        PARTITION BY yc.month ORDER BY yc.scenario
    ) as other_scenario_net_flow,

    -- Calculate opportunity cost of part-time work
    CASE
        WHEN yc.scenario = 'part_time' THEN
            yc.projected_income - LAG(yc.projected_income) OVER (
                PARTITION BY yc.month ORDER BY yc.scenario DESC
            )
        ELSE NULL
    END as part_time_opportunity_cost

FROM yoy_comparison yc
LEFT JOIN quarterly_summary qs
    ON yc.scenario = qs.scenario
    AND yc.quarter = qs.quarter
    AND yc.year = qs.year
ORDER BY yc.scenario, yc.month