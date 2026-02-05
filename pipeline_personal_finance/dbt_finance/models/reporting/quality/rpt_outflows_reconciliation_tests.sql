{{
    config(
        materialized='table',
        indexes=[
            {'columns': ['period_date'], 'unique': false},
            {'columns': ['test_name'], 'unique': false}
        ]
    )
}}

WITH params AS (
    SELECT
        COALESCE({{ var('recon_months_back', 24) }}, 24)::int AS months_back,
        COALESCE({{ var('recon_tolerance', 0.01) }}, 0.01)::numeric AS tolerance,
        COALESCE({{ var('recon_tolerance_pct', 0.02) }}, 0.02)::numeric AS tolerance_pct
),

periods AS (
    SELECT DISTINCT period_date
    FROM {{ ref('viz_detailed_outflows_breakdown') }}
    WHERE period_date >= (DATE_TRUNC('month', CURRENT_DATE) - (
            (SELECT months_back FROM params) || ' months'
        )::interval)
),

viz_monthly AS (
    SELECT 
        vdob.period_date,
    vdob.total_outflows,
    vdob.total_transactions,
    vdob.food_dining,
    vdob.household_utilities,
    vdob.housing_mortgage,
        vdob.transportation,
        vdob.shopping_retail,
        vdob.family_kids,
        vdob.health_wellness,
    vdob.entertainment,
    vdob.travel,
    vdob.gifts_charity,
    vdob.insurance,
    vdob.investments,
    vdob.taxes,
    vdob.uncategorized,
    vdob.other_expenses
    FROM {{ ref('viz_detailed_outflows_breakdown') }} vdob
    WHERE vdob.period_date IN (SELECT period_date FROM periods)
),

fact_monthly_outflows AS (
    SELECT 
        DATE_TRUNC('month', ft.transaction_date)::date AS period_date,
        SUM(ABS(ft.transaction_amount))::numeric AS total_outflows_fact,
        COUNT(*) AS total_transactions_fact
    FROM {{ ref('fct_transactions') }} ft
    WHERE ft.transaction_amount < 0
      AND NOT COALESCE(ft.is_internal_transfer, FALSE)
    GROUP BY 1
),

fact_uncategorized AS (
    SELECT 
        DATE_TRUNC('month', ft.transaction_date)::date AS period_date,
        SUM(ABS(ft.transaction_amount))::numeric AS uncategorized_fact
    FROM {{ ref('fct_transactions') }} ft
    JOIN {{ ref('dim_categories') }} dc
      ON ft.category_key = dc.category_key
    WHERE ft.transaction_amount < 0
      AND NOT COALESCE(ft.is_internal_transfer, FALSE)
      AND dc.level_1_category = 'Uncategorized'
    GROUP BY 1
),

category_sum AS (
    SELECT 
        period_date,
        (
            COALESCE(food_dining, 0) +
            COALESCE(household_utilities, 0) +
            COALESCE(housing_mortgage, 0) +
            COALESCE(transportation, 0) +
            COALESCE(shopping_retail, 0) +
            COALESCE(family_kids, 0) +
            COALESCE(health_wellness, 0) +
            COALESCE(entertainment, 0) +
            COALESCE(travel, 0) +
            COALESCE(gifts_charity, 0) +
            COALESCE(insurance, 0) +
            COALESCE(investments, 0) +
            COALESCE(taxes, 0) +
            COALESCE(uncategorized, 0) +
            COALESCE(other_expenses, 0)
        )::numeric AS total_outflows_from_categories
    FROM viz_monthly
),

-- Assemble test rows
tests AS (
    SELECT 
        v.period_date,
        'total_matches_fact'::text AS test_name,
        v.total_outflows           AS left_value,
        f.total_outflows_fact      AS right_value,
        (v.total_outflows - f.total_outflows_fact) AS delta,
        (ABS(v.total_outflows - f.total_outflows_fact) <= (SELECT tolerance FROM params)) AS pass,
        'viz.total_outflows vs fact sum(abs(negatives) excl. internal)'::text AS notes
    FROM viz_monthly v
    LEFT JOIN fact_monthly_outflows f USING (period_date)

    UNION ALL

    SELECT 
        v.period_date,
        'category_sum_coverage_ok'::text AS test_name,
        v.total_outflows                    AS left_value,
        cs.total_outflows_from_categories   AS right_value,
        (v.total_outflows - cs.total_outflows_from_categories) AS delta,
        (
          CASE WHEN v.total_outflows > 0 THEN 
            (ABS(v.total_outflows - cs.total_outflows_from_categories) / v.total_outflows)
          ELSE 0 END
        ) <= (SELECT tolerance_pct FROM params) OR 
        ABS(v.total_outflows - cs.total_outflows_from_categories) <= (SELECT tolerance FROM params) AS pass,
        'category sum covers total within tolerance_pct'::text AS notes
    FROM viz_monthly v
    LEFT JOIN category_sum cs USING (period_date)

    UNION ALL

    SELECT 
        v.period_date,
        'uncategorized_matches_fact'::text AS test_name,
        v.uncategorized                    AS left_value,
        fu.uncategorized_fact              AS right_value,
        (v.uncategorized - fu.uncategorized_fact) AS delta,
        (ABS(v.uncategorized - fu.uncategorized_fact) <= (SELECT tolerance FROM params)) AS pass,
        'viz.uncategorized vs fact sum(abs) where category = Uncategorized'::text AS notes
    FROM viz_monthly v
    LEFT JOIN fact_uncategorized fu USING (period_date)

    UNION ALL

    SELECT 
        v.period_date,
        'transaction_count_matches_fact'::text AS test_name,
        v.total_transactions                    AS left_value,
        f.total_transactions_fact               AS right_value,
        (v.total_transactions - f.total_transactions_fact)::numeric AS delta,
        (v.total_transactions = f.total_transactions_fact) AS pass,
        'viz total_transactions equals count of fact negatives excl. internal'::text AS notes
    FROM viz_monthly v
    LEFT JOIN fact_monthly_outflows f USING (period_date)
)

SELECT 
    period_date,
    test_name,
    left_value,
    right_value,
    delta,
    pass,
    notes,
    CURRENT_TIMESTAMP AS tested_at
FROM tests
ORDER BY period_date DESC, test_name
