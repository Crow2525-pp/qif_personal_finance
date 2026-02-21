# Task 107 Kickoff: Category Spending No-Data Elimination

Category: dashboard-feature
Branch: feat/task-107-category-spending-no-data-elimination

## Objective
Refactor category spending panel logic so expected-use windows do not collapse to all-empty panels.

## Required Reference Material
- .claude/references/dashboard-llm-reference.md
- scripts/check_grafana_dashboards.py
- grafana/provisioning/dashboards/*.json

## Evidence From Current State
- Most category panels return HTTP 200 but zero rows.
- Current variance filters and month assumptions over-prune outputs.

## In Scope
- Rework SQL windows and threshold logic for resilient outputs.
- Return fallback summary rows instead of blank visuals.
- Preserve analytical signal for top categories and variances.

## Implementation Plan
1. Profile available months and variance candidate counts.
2. Refactor panel SQL with safer joins and default thresholds.
3. Add fallback rows for no-threshold-hit scenarios.
4. Validate all category panels end-to-end with API and Playwright.

## Validation
1. python scripts/check_grafana_dashboards.py --dashboard category-spending-v2 --days 730
2. dbt test -s rpt_category_spending_trends+
3. Playwright verify category panels are populated or show fallback guidance.

## Acceptance Criteria
1. No expected-use category panel remains blank.
2. Variance outputs remain actionable for parents.
3. Fallback behavior is consistent across MoM and YoY panels.
