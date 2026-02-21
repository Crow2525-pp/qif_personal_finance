# Task 114 Kickoff: Tooltip Quality And Value Visibility Standard

Category: dashboard-ux-standard
Branch: feat/task-114-tooltip-quality-and-value-visibility-standard

## Objective
Standardize tooltip behavior and explicit value visibility so hover interactions consistently explain what users are seeing.

## Required Reference Material
- .claude/references/dashboard-llm-reference.md
- scripts/check_grafana_dashboards.py
- grafana/provisioning/dashboards/*.json

## Evidence From Current State
- Tooltip configuration is inconsistent across chart families.
- User requested higher quality hover details.

## In Scope
- Define minimum tooltip/value config per panel type.
- Apply explicit tooltip and label settings across affected panels.
- Add linter checks for missing tooltip/value configuration.

## Implementation Plan
1. Audit timeseries, barchart, piechart, and bargauge panels for tooltip gaps.
2. Set explicit options.tooltip.mode and value-label options where missing.
3. Ensure units and legend values are clear and consistent.
4. Extend lint script to flag non-compliant panels.

## Validation
1. python scripts/check_grafana_dashboards.py --lint-only
2. Playwright hover checks on representative core dashboards
3. Static scan confirms target panel types have explicit tooltip config

## Acceptance Criteria
1. Key charts provide meaningful hover context and values.
2. Tooltip/value rules are documented and lint-enforced.
3. No regressions to hidden or ambiguous numeric context.
