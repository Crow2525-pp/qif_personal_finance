# Task 51 Kickoff: Create a Financial Review Command Center dashboard

Category: dashboard-feature
Branch: feat/task-51-review-command-center

## Objective
Create a top-level dashboard that orchestrates the monthly review flow and links to each specialist dashboard with context.

## Scope
new grafana/provisioning/dashboards/00-financial-review-command-center.json; deep-link integration with dashboards 01-23

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
