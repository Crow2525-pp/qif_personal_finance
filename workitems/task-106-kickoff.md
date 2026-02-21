# Task 106 Kickoff: Fix Net Worth Drivers Type Safety And Fallbacks

Category: dashboard-fix
Branch: feat/task-106-fix-net-worth-drivers-type-safety-and-fallbacks

## Objective
Correct type issues in net-worth driver queries and ensure panels return meaningful output even with limited history.

## Required Reference Material
- .claude/references/dashboard-llm-reference.md
- scripts/check_grafana_dashboards.py
- grafana/provisioning/dashboards/*.json

## Evidence From Current State
- Error observed: function make_date(bigint, bigint, integer) does not exist.
- Net Worth Change Drivers (Top Account Movements) panel shows No data.

## In Scope
- Fix casting and date construction in failing net-worth query.
- Add fallback rows when history depth is insufficient.
- Keep other net-worth KPI semantics unchanged.

## Implementation Plan
1. Reproduce failing panel SQL and identify type mismatch source.
2. Apply explicit casting or compatible date-function rewrite.
3. Add guard CTEs for thin-history datasets.
4. Validate top-movement and summary driver panels in UI.

## Validation
1. python scripts/check_grafana_dashboards.py --dashboard household_net_worth
2. dbt test -s rpt_household_net_worth+
3. Playwright verify net-worth driver panels render data or fallback rows.

## Acceptance Criteria
1. No runtime type errors remain in net-worth driver SQL.
2. Driver panel is never blank in normal usage.
3. Fallback output is human-readable.
