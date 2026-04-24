{{
  config(
    materialized='table'
  )
}}

-- Recommendation outcome tracking: reads from seed and adds computed accountability columns.
-- Allows the dashboard to show whether past recommendations were acted on and what impact they had.

WITH base AS (
  SELECT
    recommendation_date::date                          AS recommendation_date,
    recommendation_text,
    category,
    target_metric,
    target_value::numeric                              AS target_value,
    actual_value::numeric                              AS actual_value,
    outcome_date::date                                 AS outcome_date,
    status,
    notes
  FROM {{ ref('recommendation_outcomes') }}
),

computed AS (
  SELECT
    recommendation_date,
    recommendation_text,
    category,
    target_metric,
    target_value,
    actual_value,
    outcome_date,
    status,
    notes,

    -- Boolean flag: was the recommendation successfully achieved?
    CASE WHEN status = 'achieved' THEN TRUE ELSE FALSE END   AS is_achieved,

    -- Variance between actual and target (positive = beat target, negative = missed)
    CASE
      WHEN actual_value IS NOT NULL AND target_value IS NOT NULL
        THEN ROUND(actual_value - target_value, 2)
      ELSE NULL
    END                                                       AS variance,

    -- Days from recommendation to outcome (NULL if not yet resolved)
    CASE
      WHEN outcome_date IS NOT NULL
        THEN (outcome_date - recommendation_date)::integer
      ELSE NULL
    END                                                       AS days_to_outcome

  FROM base
)

SELECT * FROM computed
ORDER BY recommendation_date DESC
