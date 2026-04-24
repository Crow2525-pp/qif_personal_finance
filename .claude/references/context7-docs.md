# Context7 Documentation Routing

Use Context7 for current documentation when work depends on library or product behavior rather than repo-local code.

## Project Libraries

- Dagster: orchestration, assets, sensors, resources, Docker execution, and `dagster-dbt` integration.
- dbt: model configuration, tests, macros, profiles, materializations, and `dbt-postgres` behavior.
- Grafana: dashboard JSON schema, panel options, provisioning, data source queries, and visualization units.

## Usage Rule

When a task asks "how does Dagster/dbt/Grafana do X" or touches APIs/options that may have changed, ask Context7 for the relevant docs first, then apply the answer to this repo's local conventions in `CLAUDE.md` and the scoped reference files.

Do not use Context7 to replace repo inspection. Local code, Makefile targets, dashboard JSON, dbt models, and tests remain the source of truth for this project.
