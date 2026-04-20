import logging
import os
import shutil
from pathlib import Path

from dagster_dbt import DbtCliResource

_logger = logging.getLogger(__name__)

# Keep dbt resolution pinned to the dbt project directory itself.
DBT_PROJECT_DIR = Path(__file__).resolve().parent / "dbt_finance"
DBT_TARGET_DIR = DBT_PROJECT_DIR / "target"
QIF_FILES = "pipeline_personal_finance/qif_files"
SEED_DIR = DBT_PROJECT_DIR / "seeds"
SEED_TEMPLATE_DIR = DBT_PROJECT_DIR / "seed_templates"
PRIVATE_SEED_NAMES = (
    "known_values",
    "mortgage_patch_data",
    "property_assets",
    "property_valuation_overrides",
    "recommendation_outcomes",
)


def ensure_private_seed_stubs() -> None:
    """Materialize header-only private seed stubs before dbt parses refs."""
    _logger.debug("DBT_PROJECT_DIR set to: %s", DBT_PROJECT_DIR)
    SEED_DIR.mkdir(parents=True, exist_ok=True)
    for seed_name in PRIVATE_SEED_NAMES:
        target = SEED_DIR / f"{seed_name}.csv"
        template = SEED_TEMPLATE_DIR / f"{seed_name}.template.csv"
        if not target.exists() and template.exists():
            shutil.copy2(template, target)


ensure_private_seed_stubs()

dbt = DbtCliResource(project_dir=os.fspath(DBT_PROJECT_DIR))

# If DAGSTER_DBT_PARSE_PROJECT_ON_LOAD is set, a manifest will be created at run time.
# Otherwise, we expect a manifest to be present in the project's target directory.
dbt_manifest_path = (
    dbt.cli(
        ["--quiet", "parse"],
        target_path=DBT_TARGET_DIR,
    )
    .wait()
    .target_path.joinpath("manifest.json")
)
