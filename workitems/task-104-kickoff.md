# Task 104 Kickoff: Fix Executive KPI Schema Drift And Zero-Value Contract

Category: dashboard-fix
Branch: feat/task-104-fix-executive-kpi-schema-drift-and-zero-value-contract

## Objective
Resolve stale column references and formalize when KPI panels may display zero versus fallback explanatory output.

## Required Reference Material
- .claude/references/dashboard-llm-reference.md
- scripts/check_grafana_dashboards.py
- grafana/provisioning/dashboards/*.json

## Evidence From Current State
- Error observed: column inflow_excl_transfers does not exist.
- User requirement: avoid misleading 0% or 0 values where data is missing.

## In Scope
- Align executive panel SQL with current model schema.
- Add null or insufficient-history fallback rows for KPI panels.
- Add tests for zero-value legitimacy.

## Implementation Plan
1. Trace each executive KPI field from panel SQL to dbt model.
2. Replace stale columns or introduce compatibility aliases.
3. Implement explicit fallback text or rows when numerator or denominator unavailable.
4. Add dbt tests for latest complete month KPI completeness.

## Validation
1. dbt build -s rpt_executive_dashboard+ rpt_monthly_budget_summary+
2. python scripts/check_grafana_dashboards.py --dashboard executive_dashboard
3. Playwright verify KPI cards and snapshot panel values are realistic.

## Acceptance Criteria
1. No schema-drift query failures in executive KPI panels.
2. No misleading zero displays for missing-data states.
3. Fallback behavior is explicit and consistent.
