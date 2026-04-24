# Context7 For Codex

This project has a local Context7 MCP server for Codex in `.codex/config.toml`, mirrored for JSON-based MCP clients in `.mcp.json`. Use it for current external documentation when Dagster, dbt, or Grafana behavior matters.

## Library IDs

- Dagster: `/dagster-io/dagster`
- dbt docs: `/dbt-labs/docs.getdbt.com`
- Grafana docs: `/websites/grafana`

## Routing Rule

Use Context7 for questions about current APIs, options, schemas, configuration keys, examples, and version-sensitive behavior. Typical examples: Dagster asset/resource APIs, `dagster-dbt`, dbt model/test/profile configuration, materializations, Grafana dashboard JSON, panel options, provisioning, data source query behavior, and units.

Use local repository inspection for project truth: `Makefile` targets, Docker Compose wiring, Dagster definitions, dbt models/macros/tests, dashboard JSON, scripts, fixtures, and existing conventions. Local code decides what this project currently does.

Best workflow: inspect the local repo enough to identify the exact component and project convention, query Context7 for current external docs when needed, then reconcile the docs with the local implementation. Keep Context7 prompts documentation-focused and do not send secrets, private data, or raw QIF content.
