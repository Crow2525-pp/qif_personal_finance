# Codex Project Notes

Use this file as the Codex entry point for repository-specific guidance. Keep detailed workflow notes in the referenced files and inspect only the files needed for the active task.

## Context Loading

- Start with `README.md`, this file, and the scoped files needed for the request.
- For current Dagster, dbt, or Grafana documentation, use the project-local Context7 MCP server configured in `.codex/config.toml`.
- See `docs/context7-codex.md` for the Context7 library IDs and when to prefer Context7 versus local repository inspection.
- For dbt-only work, also read `data_projects/qif_personal_finance/pipeline_personal_finance/dbt_finance/AGENTS.md`.

## Repository Shape

- `platform/` is the shared Dagster/Postgres/Grafana infrastructure layer.
- `data_projects/qif_personal_finance/` is the tracked QIF personal-finance data project.
- `data_projects/coles_llm/` is the documented Coles LLM shopper data-project slot; the active local checkout may exist separately as `coles-llm-shopper/` and should not be imported unless explicitly requested.

## Project Rules

- Prefer `make <target>` from the repository root over raw `docker compose`, `dbt`, or `uv` commands.
- Normal pipeline execution is Dagster-first: `make dagster-run`.
- Direct dbt build/test is break-glass only: `ALLOW_DIRECT_DBT=1 make dbt-build` or `ALLOW_DIRECT_DBT=1 make dbt-test`.
- Do not edit private data, `.env` secrets, QIF files, generated db files, `target/`, `logs/`, screenshots, or local backup files unless explicitly requested.
- Keep fixes scoped and verify with the narrowest relevant command before calling work complete.
