# Task 105 Kickoff: Repair Account Performance Data Contract

Category: data-contract-fix
Branch: feat/task-105-repair-account-performance-data-contract

## Objective
Fix account dashboard failures caused by missing columns and relations, and align panel queries with current reporting models.

## Required Reference Material
- .claude/references/dashboard-llm-reference.md
- scripts/check_grafana_dashboards.py
- grafana/provisioning/dashboards/*.json

## Evidence From Current State
- Errors include missing bendigo_offset and bendigo_offset_MoM.
- Error includes missing reporting.reporting__fact_transactions relation.

## In Scope
- Update panel SQL or add compatibility views for renamed columns.
- Replace deprecated relation references with canonical model.
- Add schema tests for required account fields.

## Implementation Plan
1. Inventory failing account panels and expected output schema.
2. Refactor SQL to current reporting models and aliases.
3. Add or adjust dbt compatibility model(s) if needed.
4. Re-run panel checks and ensure no blank critical panels.

## Validation
1. dbt run -s rpt_account_performance+
2. dbt test -s rpt_account_performance+
3. python scripts/check_grafana_dashboards.py --dashboard account_performance_dashboard

## Acceptance Criteria
1. Account dashboard panels execute without missing-column or missing-relation errors.
2. Critical balance and mortgage panels return usable data.
3. Required fields are test-protected.
