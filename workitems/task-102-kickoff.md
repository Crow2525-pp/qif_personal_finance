# Task 102 Kickoff: Fix Dashboard JSON Integrity And Provisioning Hardening

Category: dashboard-fix
Branch: feat/task-102-dashboard-json-integrity-and-provisioning-hardening

## Objective
Repair malformed dashboard JSON files and enforce a guard so Grafana provisioning cannot silently fail on invalid control characters.

## Required Reference Material
- .claude/references/dashboard-llm-reference.md
- scripts/check_grafana_dashboards.py
- grafana/provisioning/dashboards/*.json

## Evidence From Current State
- Parse errors in outflows-insights-dashboard.json and transaction-analysis-dashboard.json.
- Grafana provisioning logs show failed dashboard loads for those files.

## In Scope
- Sanitize invalid control characters and preserve dashboard intent.
- Add lint/guard for UTF-8 and parse validity.
- Document pre-merge JSON integrity check.

## Implementation Plan
1. Identify and remove offending control characters from both files.
2. Reformat and validate JSON deterministically.
3. Extend lint workflow to fail on parse errors and control chars.
4. Re-run provisioning and confirm dashboards load cleanly.

## Validation
1. python scripts/check_grafana_dashboards.py --lint-only
2. docker compose logs --tail=200 grafana
3. Open both dashboards in Grafana and confirm they load.

## Acceptance Criteria
1. Both dashboards provision successfully.
2. Integrity guard prevents recurrence.
3. No accidental panel loss from sanitation.
