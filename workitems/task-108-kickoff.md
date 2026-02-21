# Task 108 Kickoff: Implement Recommendation Outcomes Data Loop

Category: dashboard-feature
Branch: feat/task-108-recommendation-outcomes-data-loop

## Objective
Create the missing recommendation outcomes reporting dataset and wire it into executive recommendation tracking.

## Required Reference Material
- .claude/references/dashboard-llm-reference.md
- scripts/check_grafana_dashboards.py
- grafana/provisioning/dashboards/*.json

## Evidence From Current State
- Error observed: relation reporting.rpt_recommendation_outcomes does not exist.
- Executive recommendation tracker cannot show status or impact currently.

## In Scope
- Create recommendation outcomes model and tests.
- Update executive tracker query to use new model.
- Ensure panel shows meaningful status and impact values.

## Implementation Plan
1. Define minimal schema: recommendation_id, status, owner, due_month, impact metrics.
2. Implement dbt model (or staged seed + model) producing current-state rows.
3. Update panel query and fields in executive dashboard.
4. Add dbt tests and verify panel output.

## Validation
1. dbt run -s rpt_recommendation_outcomes+
2. dbt test -s rpt_recommendation_outcomes+
3. python scripts/check_grafana_dashboards.py --dashboard executive_dashboard

## Acceptance Criteria
1. Recommendation tracker renders non-empty actionable records.
2. Model is documented and test-covered.
3. Panel supports follow-up decision loops for parents.
