# QIF Personal Finance Data Project

This folder contains the original personal-finance project after the repository was split into platform infrastructure and data projects.

- `pipeline_personal_finance/` is the Dagster code location and Python package.
- `pipeline_personal_finance/dbt_finance/` is the finance dbt project.
- `pipeline_personal_finance/qif_files/` is the local QIF mount point and remains private/local data.

Use repository-root `make` targets for normal operation. Direct dbt commands remain break-glass only unless the scoped dbt docs say otherwise.
