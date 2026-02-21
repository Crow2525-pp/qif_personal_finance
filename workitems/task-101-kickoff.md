# Task 101 Kickoff: Build Dashboard QA Observability Harness

Category: dashboard-quality
Branch: feat/task-101-dashboard-qa-observability-harness

## Objective
Create a repeatable quality harness that runs lint, Grafana API checks, and Playwright evidence capture in one command.

## Required Reference Material
- .claude/references/dashboard-llm-reference.md
- scripts/check_grafana_dashboards.py
- grafana/provisioning/dashboards/*.json

## Evidence From Current State
- Dashboard quality checks are fragmented and manual today.
- No single task artifact bundles lint/query/visual failures for LLM triage.

## In Scope
- Add orchestrator script for lint + live checks + screenshots.
- Persist JSON/markdown/screenshot artifacts under timestamped folder.
- Document local/CI usage for contributors.

## Implementation Plan
1. Implement scripts/dashboard_quality_gate.py orchestrating existing checker and Playwright review steps.
2. Normalize failures by dashboard/panel/rule and write summary report.
3. Add CLI targeting (--dashboards, --lint-only, --screenshots) and fail thresholds.
4. Update docs in grafana/provisioning/dashboards/README.md.

## Validation
1. python scripts/dashboard_quality_gate.py --help
2. python scripts/dashboard_quality_gate.py --dashboards executive_dashboard category-spending-v2
3. Confirm report and screenshots are generated.

## Acceptance Criteria
1. Single command produces actionable QA artifacts.
2. Report includes static + query + Playwright findings.
3. Output is concise enough for quick fix planning.
