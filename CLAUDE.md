# qif_personal_finance - Claude Code Context

This is the standing operating guide for Claude Code in this repository. Keep it short, load referenced files only when relevant, and prefer repo commands over ad-hoc shell commands.

## Project Map

- Purpose: monthly personal finance QIF ingestion, dbt transformations, and Grafana dashboards for household spend awareness.
- Runtime: Docker Compose stack with Dagster, PostgreSQL, dbt, and Grafana.
- Python/deps: `uv` workspace from the repo root.
- Orchestration source: `platform/dagster_core/` and `data_projects/qif_personal_finance/pipeline_personal_finance/`.
- dbt source: `data_projects/qif_personal_finance/pipeline_personal_finance/dbt_finance/`.
- Dashboard source of truth: `platform/grafana/provisioning/dashboards/*.json`.
- Local/private data: `.env*`, QIF files, generated db/dbt artifacts, screenshots, and most CSVs must not be committed.

## Context Loading Rules

- Start with this file, `README.md`, and the specific files needed for the task.
- For pipeline or dashboard behavior, read `.claude/pipeline-context.md`.
- For dashboard-specific work, read `.claude/references/dashboard-llm-reference.md` and `platform/grafana/provisioning/dashboards/README.md`.
- For dbt-only work, read `data_projects/qif_personal_finance/pipeline_personal_finance/dbt_finance/AGENTS.md`.
- For current Dagster, dbt, or Grafana API/docs questions, use Context7 instead of relying on model memory.
- Do not bulk-read dashboard JSON, dbt models, or generated artifacts. Use `rg`/targeted file reads first.
- Use subagents for broad grep, impact scans, or independent verification when available; keep the main context for decisions and edits.

## Hard Rules

- Prefer `make <target>` from the repo root over raw `docker compose`, `dbt`, or `uv` commands.
- Normal pipeline execution is Dagster-first: `make dagster-run`.
- Direct dbt build/test is break-glass only: `ALLOW_DIRECT_DBT=1 make dbt-build` or `ALLOW_DIRECT_DBT=1 make dbt-test`.
- Do not add automated file watchers, cron jobs, scheduled Dagster triggers, streaming, or realtime dashboard behavior unless explicitly requested.
- Do not edit private data, `.env` secrets, QIF files, generated db files, `target/`, `logs/`, screenshots, or local backup files unless explicitly requested.
- Do not broaden Claude shell permissions or add destructive commands without explicit approval.
- Keep fixes scoped. One bugfix should touch the smallest practical set of files.
- Never say a task is done without running the relevant verification command, or explicitly stating why verification could not be run.

## Common Commands

```bash
make help
make bootstrap-worktree
make up
make status
make logs
make dagster-run
make lint
make dbt-compile
uv run pytest -q
python scripts/check_grafana_dashboards.py --lint-only
```

## Verification Matrix

- Python changes: `uv run pytest -q`.
- dbt model or macro changes: `make dbt-compile` first; use `ALLOW_DIRECT_DBT=1 make dbt-test` only when a real dbt test run is needed and appropriate.
- SQL style changes: `make lint`.
- Dagster/pipeline integration changes: `make dagster-run` when the stack is running; otherwise report that Docker services were unavailable.
- Dashboard JSON changes: `python scripts/check_grafana_dashboards.py --lint-only`.
- Dashboard runtime changes: targeted `python scripts/check_grafana_dashboards.py --dashboard <uid-or-title> --days 365` plus Playwright/Grafana screenshot review when credentials and services are available.
- Compose/deployment changes: `docker compose config --quiet` after creating/populating `.env` as needed.

## Architecture Notes

- Data flow: QIF files -> Dagster ingestion -> PostgreSQL `landing` -> dbt `staging` -> `transformation` -> `reporting` -> Grafana dashboards.
- Supported source banks include Adelaide Bank, Bendigo Bank, and ING.
- PostgreSQL roles matter: `postgres` is admin, `dagster_service` writes via Dagster/dbt, and `grafanareader` is dashboard read-only.
- The pipeline is manual and low-frequency. Simplicity beats abstractions optimized for scale or realtime behavior.
- Grafana currency display should use `$`, not `A$`, per existing dashboard convention.
- Percent conventions: ratio fields use `percentunit` and 0-1 values; `*_pct` fields use `percent` and 0-100 values.

## Memory And Retros

- Keep durable project notes under `.claude/memory/` with short typed markdown files: `project_*`, `feedback_*`, `reference_*`, or `user_*`.
- Maintain `.claude/memory/MEMORY.md` as the index so future sessions can load only relevant memory.
- After non-trivial sessions, write a short retro under `docs/retros/YYYY-MM-DD-topic.md` covering goal, changed files, verification, and follow-ups.
- At session start, read the latest retro only if it is relevant to the current task.
