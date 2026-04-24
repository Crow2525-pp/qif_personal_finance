{{ config(materialized='table') }}

WITH base_assumptions AS (
    SELECT
        -- Scenario parameters
        'full_time' as scenario,
        1.0 as work_factor,

        -- Growth assumptions based on last 3 years
        0.05 as income_growth_rate,  -- 5% annual income growth
        0.04 as expense_growth_rate, -- 4% annual expense growth
        0.02 as inflation_rate,      -- 2% inflation

        -- Current baseline (from recent 6 months)
        3800.0 as monthly_qbe_base,     -- Steph's full-time QBE salary
        1400.0 as monthly_education_base, -- Education work when active
        2900.0 as monthly_phil_base,    -- Phil's contribution

        -- Other income assumptions
        12000.0 as annual_bonus,        -- Annual bonus/irregular income
        2000.0 as annual_tax_refund     -- Annual tax refund

    UNION ALL

    SELECT
        'part_time' as scenario,
        0.6 as work_factor,  -- 3 days a week = 0.6 of full time

        0.03 as income_growth_rate,  -- Lower growth for part-time
        0.04 as expense_growth_rate, -- Same expense growth
        0.02 as inflation_rate,

        3800.0 as monthly_qbe_base,
        1400.0 as monthly_education_base,
        2900.0 as monthly_phil_base,

        7000.0 as annual_bonus,      -- Reduced bonus for part-time
        2000.0 as annual_tax_refund
),

monthly_projections AS (
    SELECT
        bp.*,

        -- Calculate monthly income for each scenario
        (monthly_qbe_base * work_factor) +
        (monthly_education_base * 0.3) +  -- Assume 30% of months have education work
        monthly_phil_base as base_monthly_income,

        -- Project forward 12 months
        {% if target.type == 'duckdb' %}
        UNNEST(range(1, 13)) AS projection_month
        {% else %}
        generate_series(1, 12) AS projection_month
        {% endif %}

    FROM base_assumptions bp
)

SELECT
    mp.*,

    -- Calculate date for projection
    DATE_TRUNC('month', CURRENT_DATE) + INTERVAL '1 month' * (projection_month - 1) as projection_date,

    -- Calculate projected monthly income with growth
    base_monthly_income * POWER(1 + (income_growth_rate / 12), projection_month) as projected_monthly_income,

    -- Add bonus allocation (spread across year)
    (annual_bonus / 12.0) as monthly_bonus_allocation,
    (annual_tax_refund / 12.0) as monthly_tax_refund_allocation

FROM monthly_projections mp
ORDER BY scenario, projection_month
