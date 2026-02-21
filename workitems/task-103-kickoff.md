# Task 103 Kickoff: Restore Executive Reporting Model Compatibility

Category: data-contract-fix
Branch: feat/task-103-restore-executive-reporting-model-compatibility

## Objective
Re-establish the reporting contract needed by executive-related dashboards by restoring or compat-wrapping reporting.rpt_executive_dashboard.

## Required Reference Material
- .claude/references/dashboard-llm-reference.md
- scripts/check_grafana_dashboards.py
- grafana/provisioning/dashboards/*.json

## Evidence From Current State
- Panel errors include relation reporting.rpt_executive_dashboard does not exist.
- Failures affect executive, expense-performance, and mobile executive dashboards.

## In Scope
- Implement missing relation or compatibility model.
- Document required columns used by dashboards.
- Add dbt tests to lock the contract.

## Implementation Plan
1. Map all panel queries depending on rpt_executive_dashboard.
2. Create or restore model with required fields and latest-month semantics.
3. Add schema tests for required fields and not-null expectations.
4. Revalidate impacted dashboards.

## Validation
1. dbt run -s rpt_executive_dashboard+
2. dbt test -s rpt_executive_dashboard+
3. python scripts/check_grafana_dashboards.py --dashboard executive_dashboard --dashboard expense_performance --dashboard exec-mobile-overview

## Acceptance Criteria
1. No missing-relation errors remain for executive contract.
2. Affected panels render data.
3. Contract is tested and documented.
