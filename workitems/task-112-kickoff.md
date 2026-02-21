# Task 112 Kickoff: Text Content Sanitization And KPI Docs Refresh

Category: content-quality
Branch: feat/task-112-text-content-sanitization-and-kpi-docs-refresh

## Objective
Remove markdown artifacts, emojis, and file-path references from dashboard-facing text while keeping formulas and metric explanations clear.

## Required Reference Material
- .claude/references/dashboard-llm-reference.md
- scripts/check_grafana_dashboards.py
- grafana/provisioning/dashboards/*.json

## Evidence From Current State
- Text panels contain markdown headings/bullets and emoji-rich titles.
- Savings KPI panel includes direct markdown file path reference.

## In Scope
- Rewrite text panels into plain language content.
- Remove user-visible markdown/file-path artifacts.
- Retain and verify KPI formula accuracy.

## Implementation Plan
1. Inventory text panels with markdown or emoji content.
2. Apply plain-language style guide across instruction/KPI panels.
3. Replace file-path references with concise in-panel formula definitions.
4. Verify rendered text readability in Playwright.

## Validation
1. python scripts/check_grafana_dashboards.py --lint-only
2. Repo search for emoji/markdown tokens in dashboard titles and text panels
3. Playwright verify updated text in executive, savings, category dashboards

## Acceptance Criteria
1. No parent-facing titles/text contain emoji, markdown syntax, or path references.
2. Formulas remain correct and understandable.
3. Instruction panels are concise and readable.
