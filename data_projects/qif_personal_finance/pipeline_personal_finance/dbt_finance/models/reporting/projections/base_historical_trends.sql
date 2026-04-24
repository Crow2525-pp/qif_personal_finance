{{ config(materialized='table') }}

WITH monthly_aggregates AS (
    SELECT
        DATE_TRUNC('month', t.transaction_date) as month,
        EXTRACT(year FROM t.transaction_date) as year,
        EXTRACT(month FROM t.transaction_date) as month_num,

        -- Income breakdowns
        SUM(CASE WHEN t.transaction_memo LIKE '%QBE MANAGEMENT%' THEN t.transaction_amount ELSE 0 END) as qbe_salary,
        SUM(CASE WHEN t.transaction_memo LIKE '%DEPARTMENT OF ED%' THEN t.transaction_amount ELSE 0 END) as education_salary,
        SUM(CASE WHEN t.transaction_memo LIKE '%Phil pay Stephanie%' THEN t.transaction_amount ELSE 0 END) as phil_payments,
        SUM(CASE WHEN t.transaction_amount > 0 THEN t.transaction_amount ELSE 0 END) as total_income,

        -- Expense breakdown
        SUM(CASE WHEN t.transaction_amount < 0 THEN ABS(t.transaction_amount) ELSE 0 END) as total_expenses,
        SUM(t.transaction_amount) as net_flow,

        -- Transaction counts
        COUNT(CASE WHEN t.transaction_amount > 0 THEN 1 END) as income_transactions,
        COUNT(CASE WHEN t.transaction_amount < 0 THEN 1 END) as expense_transactions

    FROM {{ ref('fct_transactions') }} t
    WHERE t.transaction_date >= '2022-01-01'
        AND t.transaction_date < DATE_TRUNC('month', CURRENT_DATE)  -- Only complete months
    GROUP BY
        DATE_TRUNC('month', t.transaction_date),
        EXTRACT(year FROM t.transaction_date),
        EXTRACT(month FROM t.transaction_date)
),

yearly_trends AS (
    SELECT
        year,
        AVG(qbe_salary) as avg_monthly_qbe_salary,
        AVG(education_salary) as avg_monthly_education_salary,
        AVG(phil_payments) as avg_monthly_phil_payments,
        AVG(total_income) as avg_monthly_income,
        AVG(total_expenses) as avg_monthly_expenses,
        AVG(net_flow) as avg_monthly_net_flow,

        -- Year-over-year growth rates
        LAG(AVG(total_income)) OVER (ORDER BY year) as prev_year_avg_income,
        LAG(AVG(total_expenses)) OVER (ORDER BY year) as prev_year_avg_expenses

    FROM monthly_aggregates
    GROUP BY year
)

SELECT
    ma.*,
    yt.avg_monthly_income as year_avg_income,
    yt.avg_monthly_expenses as year_avg_expenses,
    yt.prev_year_avg_income,
    yt.prev_year_avg_expenses,

    -- Calculate growth rates
    CASE
        WHEN yt.prev_year_avg_income > 0 THEN
            (yt.avg_monthly_income - yt.prev_year_avg_income) / yt.prev_year_avg_income
        ELSE 0
    END as income_growth_rate,

    CASE
        WHEN yt.prev_year_avg_expenses > 0 THEN
            (yt.avg_monthly_expenses - yt.prev_year_avg_expenses) / yt.prev_year_avg_expenses
        ELSE 0
    END as expense_growth_rate

FROM monthly_aggregates ma
LEFT JOIN yearly_trends yt ON ma.year = yt.year
ORDER BY ma.month