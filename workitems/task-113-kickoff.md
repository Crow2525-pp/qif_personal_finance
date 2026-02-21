# Task 113 Kickoff: Visual Semantics Audit And Chart Refactor

Category: visual-design-improvement
Branch: feat/task-113-visual-semantics-audit-and-chart-refactor

## Objective
Audit chart-type choices and convert mismatched visuals to better encodings for trend and comparison tasks.

## Required Reference Material
- .claude/references/dashboard-llm-reference.md
- scripts/check_grafana_dashboards.py
- grafana/provisioning/dashboards/*.json

## Evidence From Current State
- Pie charts and other visuals are used in places where comparison/trend reading is harder.
- User requested avoiding visuals that do not match message intent.

## In Scope
- Define chart-selection rubric by analytical question type.
- Convert identified panels to better chart types with minimal disruption.
- Adjust query field shape/labels as needed for new visuals.

## Implementation Plan
1. Catalog candidate panels by current type and intended insight.
2. Choose replacement types (bar/line/table) with rationale.
3. Refactor panel JSON and field configs to support new visual.
4. Capture before/after screenshots and confirm improved readability.

## Validation
1. python scripts/check_grafana_dashboards.py --dashboard category-spending-v2 --dashboard financial_projections
2. Playwright screenshot comparisons for converted panels
3. Manual review with focus on ranking and trend readability

## Acceptance Criteria
1. Converted visuals better match the panel question.
2. No loss of required numeric context after conversion.
3. Comparison and trend interpretation is faster for parents.
