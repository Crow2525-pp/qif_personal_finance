# Task 46 Kickoff: Restore Mortgage Payoff dashboard source-model contract

Category: dashboard-fix
Branch: feat/task-46-mortgage-source-model-contract

## Objective
Rebuild or retarget missing mortgage payoff source relations and validate every panel resolves with no missing relation errors.

## Scope
grafana/provisioning/dashboards/15-mortgage-payoff.json; pipeline_personal_finance/dbt_finance/models/reporting/mortgage/*.sql; pipeline_personal_finance/dbt_finance/models/reporting/schema.yml

## PR-Sized Deliverables
1. Implement the core change set for this task only (no cross-task coupling).
2. Add/adjust validation so regressions for this task are detectable.
3. Provide evidence artifacts (before/after query or screenshot or checker output).

## Acceptance Criteria
1. Changes are confined to task scope and pass repo checks relevant to touched files.
2. Dashboard behavior and/or upstream model contract is improved in the intended direction.
3. PR description includes a decision-focused summary and explicit non-goals.

## Initial Execution Plan
1. Reproduce current gap with concrete panel/query evidence.
2. Implement minimal robust fix/feature with tests or checker updates.
3. Capture verification output and update PR notes.
