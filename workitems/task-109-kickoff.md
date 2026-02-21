# Task 109 Kickoff: Remove Child Parameter And Introduce Family Profile Constants

Category: ux-simplification
Branch: feat/task-109-remove-child-parameter-and-family-profile-constants

## Objective
Remove mutable child-count controls from dashboards and centralize fixed family profile constants (children=3) in data logic.

## Required Reference Material
- .claude/references/dashboard-llm-reference.md
- scripts/check_grafana_dashboards.py
- grafana/provisioning/dashboards/*.json

## Evidence From Current State
- Executive dashboard exposes child_count selector 1-6.
- User requirement states this parameter is unnecessary and confusing.

## In Scope
- Delete child_count dashboard variable and UI control.
- Move child-count assumptions to a canonical constant source.
- Update per-child metrics and labels accordingly.

## Implementation Plan
1. Find all dashboard SQL and model logic referencing child_count.
2. Create shared family-profile constant in dbt model/macro.
3. Refactor panel queries to use constant-backed values.
4. Verify UI no longer shows child parameter.

## Validation
1. python scripts/check_grafana_dashboards.py --dashboard executive_dashboard
2. Playwright confirm no child selector appears
3. dbt test for affected per-child metrics

## Acceptance Criteria
1. No child-count parameter remains in dashboard UI.
2. Per-child metrics still compute correctly for family size 3.
3. Parent-facing controls are simplified.
