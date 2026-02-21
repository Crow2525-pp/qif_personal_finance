# Task 115 Kickoff: Desktop Layout Alignment And Mobile De-Emphasis

Category: layout-refactor
Branch: feat/task-115-desktop-layout-alignment-and-mobile-deemphasis

## Objective
Apply structured desktop-first layout alignment to core dashboards and reduce mobile-first prominence in navigation.

## Required Reference Material
- .claude/references/dashboard-llm-reference.md
- scripts/check_grafana_dashboards.py
- grafana/provisioning/dashboards/*.json

## Evidence From Current State
- User preference is structured aligned desktop dashboards and ordered review flow.
- Current dashboard suite mixes desktop/mobile emphasis inconsistently.

## In Scope
- Define desktop layout rubric (row sections, grid rhythm, spacing).
- Refactor core dashboard panel placement to follow rubric.
- Update navigation to prioritize desktop dashboards over mobile-only paths.

## Implementation Plan
1. Create alignment spec with reusable grid patterns for KPI, trend, and detail sections.
2. Refactor executive, cash-flow, monthly-budget, category layouts to align sections.
3. Update command-center and links to highlight desktop-first sequence.
4. Capture before/after full-page screenshots for review.

## Validation
1. Playwright full-page screenshots for impacted dashboards
2. python scripts/check_grafana_dashboards.py --dashboard executive_dashboard --dashboard cash_flow_analysis --dashboard monthly_budget_summary
3. Manual scan confirms consistent row/column alignment

## Acceptance Criteria
1. Core desktop dashboards follow consistent visual alignment.
2. Navigation prioritizes desktop review workflow.
3. Review requires less scrolling/context switching for parents.
