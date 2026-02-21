# Task 111 Kickoff: Dashboard Ordering, Navigation, And Link Safety

Category: information-architecture
Branch: feat/task-111-dashboard-ordering-navigation-and-link-safety

## Objective
Implement explicit ordered desktop-first navigation (01, 02, ...) and enforce link safety checks for all dashboard references.

## Required Reference Material
- .claude/references/dashboard-llm-reference.md
- scripts/check_grafana_dashboards.py
- grafana/provisioning/dashboards/*.json

## Evidence From Current State
- Current naming/order is mixed and harder to scan quickly.
- User requested ordered list and no links to missing pages.

## In Scope
- Define canonical dashboard order and titles.
- Update command-center and dashboard links to match order.
- Add automated UID-link validation (dashboard links + text-panel links).

## Implementation Plan
1. Publish canonical ordering map for desktop review flow.
2. Refactor navigation links/titles to align with map.
3. Implement link checker script and wire into lint process.
4. Validate end-to-end navigation in Playwright.

## Validation
1. Run link checker over grafana/provisioning/dashboards
2. python scripts/check_grafana_dashboards.py --lint-only
3. Playwright click-through of ordered dashboard flow

## Acceptance Criteria
1. Ordered dashboard flow is explicit and stable.
2. No link targets a missing dashboard UID.
3. Parents can follow review path without navigation dead ends.
