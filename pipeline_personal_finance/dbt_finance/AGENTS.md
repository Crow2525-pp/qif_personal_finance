# Repository Guidelines

## Project Structure & Module Organization
- `models/`: dbt models organized by domain — `staging/`, `transformation/`, `reporting/`.
- `macros/`: reusable SQL/Jinja macros (e.g., constraint management, categorisation).
- `tests/`: custom data tests and `schema.yml` for generic tests.
- `seeds/`: CSV seed data with `seeds.yml` config.
- `snapshots/`: snapshot definitions.
- `analyses/`: ad‑hoc/analysis queries.
- Root configs: `dbt_project.yml`, `packages.yml`, `profiles.yml`, `.sqlfluff*`.
- Generated: `target/` (artifacts) and `logs/` (dbt logs).

## Build, Test, and Development Commands
- Use local profile: `DBT_PROFILES_DIR=. dbt debug` (validate connection).
- Install packages: `dbt deps`.
- Compile only: `dbt compile` (fast syntax check).
- Build all (models+tests+snapshots+seeds): `dbt build`.
- Run subset: `dbt run -s models/staging` or `dbt run -s model_name`.
- Tests only: `dbt test` or `dbt test -s test_name`.
- Seeds: `dbt seed` (use `--full-refresh` when changing CSVs).
- Docs: `dbt docs generate` and `dbt docs serve` (local site).

## Coding Style & Naming Conventions
- SQL style enforced by SQLFluff (`.sqlfluff`): run `sqlfluff lint` and `sqlfluff fix --diff`.
- Indent with 4 spaces; UPPERCASE SQL keywords; one CTE per line; trailing commas.
- Use snake_case for models, columns, macros; prefer descriptive, domain‑specific names.
- Place Jinja logic in `macros/` when reusable; keep models declarative.

## Testing Guidelines
- Add schema tests in `tests/schema.yml` (e.g., `not_null`, `unique`, `relationships`).
- Put custom data tests in `tests/` as `test_*.sql` with clear intent.
- New/changed models must include basic constraints and at least one data validation.
- Run `dbt build` locally before opening a PR.

## Commit & Pull Request Guidelines
- Conventional Commits: `feat:`, `fix:`, `refactor:`, `docs:`, `chore:`.
- Keep PRs focused; include:
  - What/why, affected models/macros, and run commands used.
  - Links to issues; screenshots or notes from `dbt docs` if relevant.
  - Confirmation that `dbt build` passes locally.

## Security & Configuration Tips
- Do not commit secrets. Use env vars via `env_var()` in `profiles.yml`/Jinja.
- Avoid committing sensitive seed data; anonymize where possible.
- Large artifacts in `target/` and `logs/` are generated; review before committing.

## Agent-Specific Instructions
- Do not rename core folders. Place new models under the correct subfolder.
- Prefer macros for repeated logic and keep style compliant with SQLFluff.
- Validate with `dbt parse`/`compile` before broader changes.
