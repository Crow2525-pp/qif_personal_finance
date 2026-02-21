# Task 49 Kickoff: Harden dashboard validation tooling for CI-grade signal

Category: dashboard-fix
Branch: feat/task-49-validator-ci-signal

## Objective
Produce deterministic, non-duplicated, machine-readable validation output suitable for CI gating.

## Scope
pipeline_personal_finance/dbt_finance/scripts/validate_grafana_dashboards.py; scripts/check_grafana_dashboards.py; scripts/README.md

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
