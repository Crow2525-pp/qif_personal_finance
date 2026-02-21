# Task 110 Kickoff: Native Time Picker Unification Across Dashboards

Category: dashboard-ux-standard
Branch: feat/task-110-native-timepicker-unification

## Objective
Standardize all core dashboards on native Grafana time picker and remove competing custom date controls where feasible.

## Required Reference Material
- .claude/references/dashboard-llm-reference.md
- scripts/check_grafana_dashboards.py
- grafana/provisioning/dashboards/*.json

## Evidence From Current State
- Dashboards mix native picker with time_window and dashboard_period variables.
- Executive dashboard currently hides native time picker.

## In Scope
- Define one time-control policy for reviewed dashboards.
- Refactor SQL to use native picker macros consistently.
- Update links to pass only url time range context.

## Implementation Plan
1. Inventory template date variables and hard-coded period logic.
2. Unhide or standardize native time picker across targets.
3. Replace conflicting CURRENT_DATE logic with time macro filters when needed.
4. Update cross-dashboard links and remove stale variable forwarding.

## Validation
1. python scripts/check_grafana_dashboards.py --dashboard executive_dashboard --dashboard cash_flow_analysis --dashboard savings_analysis
2. Playwright verify consistent timepicker behavior and persisted range across links
3. Manual query check for selected historical windows

## Acceptance Criteria
1. Native picker is the only date control in target dashboards.
2. Time range behavior is consistent and predictable.
3. No dashboard relies on hidden conflicting date state.
