import logging
import os
import shutil
from pathlib import Path
from typing import Callable

from dagster_dbt import DbtCliResource

_logger = logging.getLogger(__name__)

# Keep dbt resolution pinned to the dbt project directory itself.
DBT_PROJECT_DIR = Path(__file__).resolve().parent / "dbt_finance"
DBT_TARGET_DIR = DBT_PROJECT_DIR / "target"
QIF_FILES = "data_projects/qif_personal_finance/pipeline_personal_finance/qif_files"
SEED_DIR = DBT_PROJECT_DIR / "seeds"
SEED_TEMPLATE_DIR = DBT_PROJECT_DIR / "seed_templates"
PRIVATE_SEED_NAMES = (
    "known_values",
    "mortgage_patch_data",
    "property_assets",
    "property_valuation_overrides",
    "recommendation_outcomes",
)
_PARSE_ON_LOAD_TRUTHY = {"1", "true", "yes", "on"}


def ensure_private_seed_stubs(
    *,
    seed_dir: Path = SEED_DIR,
    template_dir: Path = SEED_TEMPLATE_DIR,
    seed_names: tuple[str, ...] = PRIVATE_SEED_NAMES,
) -> None:
    """Materialize header-only private seed stubs before dbt parses refs."""
    _logger.debug("DBT project directory set to: %s", DBT_PROJECT_DIR)
    seed_dir.mkdir(parents=True, exist_ok=True)
    for seed_name in seed_names:
        target = seed_dir / f"{seed_name}.csv"
        template = template_dir / f"{seed_name}.template.csv"
        if not target.exists() and template.exists():
            shutil.copy2(template, target)


def parse_project_on_load_enabled(raw_value: str | None = None) -> bool:
    value = raw_value
    if value is None:
        value = os.getenv("DAGSTER_DBT_PARSE_PROJECT_ON_LOAD", "")
    return value.strip().lower() in _PARSE_ON_LOAD_TRUTHY


def build_dbt_resource(project_dir: Path = DBT_PROJECT_DIR) -> DbtCliResource:
    return DbtCliResource(project_dir=os.fspath(project_dir))


def resolve_dbt_manifest_path(
    *,
    project_dir: Path = DBT_PROJECT_DIR,
    target_dir: Path = DBT_TARGET_DIR,
    parse_on_load: bool | None = None,
    resource_factory: Callable[[Path], DbtCliResource] = build_dbt_resource,
    ensure_seed_stubs: Callable[[], None] = ensure_private_seed_stubs,
) -> Path:
    """Return the dbt manifest path, parsing only when explicitly requested."""
    manifest_path = target_dir / "manifest.json"
    should_parse_on_load = (
        parse_project_on_load_enabled() if parse_on_load is None else parse_on_load
    )

    if manifest_path.exists() or not should_parse_on_load:
        return manifest_path

    ensure_seed_stubs()

    try:
        cli_invocation = resource_factory(project_dir).cli(
            ["--quiet", "parse"],
            target_path=target_dir,
        )
        return cli_invocation.wait().target_path.joinpath("manifest.json")
    except FileNotFoundError as exc:
        raise RuntimeError(
            "dbt manifest not found at "
            f"{manifest_path} and dbt CLI is unavailable to regenerate it. "
            "Restore target/manifest.json, run `dbt deps`, "
            "or run `uv run dbt parse --project-dir data_projects/qif_personal_finance/pipeline_personal_finance/dbt_finance`."
        ) from exc
    except Exception as exc:
        raise RuntimeError(
            f"Failed to generate dbt manifest at {manifest_path}: {exc}"
        ) from exc


dbt_manifest_path = resolve_dbt_manifest_path()
