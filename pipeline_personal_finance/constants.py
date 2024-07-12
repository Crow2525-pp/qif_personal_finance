# dagster_finance/constants.py

import os
from pathlib import Path

import logging
from dagster_dbt import DbtCliResource

DBT_PROJECT_DIR = Path(__file__).joinpath("..", "..", "dbt_finance").resolve()

# Log the DBT_PROJECT_DIR when the application starts or when it's used
logging.info(f"DBT_PROJECT_DIR set to: {DBT_PROJECT_DIR}")

dbt = DbtCliResource(project_dir=os.fspath(DBT_PROJECT_DIR))

# If DAGSTER_DBT_PARSE_PROJECT_ON_LOAD is set, a manifest will be created at run time.
# Otherwise, we expect a manifest to be present in the project's target directory.
dbt_manifest_path = (
    dbt.cli(
        ["--quiet", "parse"],
        target_path=Path("target"),
    )
    .wait()
    .target_path.joinpath("manifest.json")
)
