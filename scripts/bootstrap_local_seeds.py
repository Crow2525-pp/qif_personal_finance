#!/usr/bin/env python3
"""Bootstrap private local data for this worktree from shared local stores."""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
from pathlib import Path


SEED_FILES = [
    "data_projects/qif_personal_finance/pipeline_personal_finance/dbt_finance/seeds/known_values.csv",
    "data_projects/qif_personal_finance/pipeline_personal_finance/dbt_finance/seeds/mortgage_patch_data.csv",
    "data_projects/qif_personal_finance/pipeline_personal_finance/dbt_finance/seeds/property_assets.csv",
    "data_projects/qif_personal_finance/pipeline_personal_finance/dbt_finance/seeds/property_valuation_overrides.csv",
    "data_projects/qif_personal_finance/pipeline_personal_finance/dbt_finance/seeds/recommendation_outcomes.csv",
]

QIF_RELATIVE_DIR = "data_projects/qif_personal_finance/pipeline_personal_finance/qif_files"
TEMPLATE_RELATIVE_DIR = "data_projects/qif_personal_finance/pipeline_personal_finance/dbt_finance/seed_templates"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def resolve_shared_dir(cli_value: str | None) -> Path:
    if cli_value:
        return Path(cli_value).expanduser().resolve()
    env_value = os.getenv("QIF_SHARED_SEED_DIR")
    if env_value:
        return Path(env_value).expanduser().resolve()
    return (Path.home() / ".qif_personal_finance" / "shared_seeds").resolve()


def resolve_shared_qif_dir() -> Path:
    env_value = os.getenv("QIF_SHARED_QIF_DIR")
    if env_value:
        return Path(env_value).expanduser().resolve()
    return (Path.home() / ".qif_personal_finance" / "shared_qif_files").resolve()


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def copy_if_missing(source: Path, destination: Path) -> bool:
    if destination.exists():
        return False
    ensure_parent(destination)
    shutil.copy2(source, destination)
    return True


def iter_qif_files(directory: Path) -> list[Path]:
    if not directory.exists():
        return []

    return sorted(
        path for path in directory.iterdir() if path.is_file() and path.suffix.lower() == ".qif"
    )


def materialize(shared_path: Path, target_path: Path, mode: str) -> str:
    ensure_parent(target_path)
    if target_path.exists():
        if sha256(shared_path) == sha256(target_path):
            return "already-present"
        shutil.copy2(shared_path, target_path)
        return "updated-copy"

    if mode in ("auto", "hardlink"):
        try:
            os.link(shared_path, target_path)
            return "created-hardlink"
        except OSError:
            if mode == "hardlink":
                raise

    shutil.copy2(shared_path, target_path)
    return "created-copy"


def bootstrap_seed_files(repo_root: Path, shared_dir: Path, mode: str) -> list[str]:
    messages: list[str] = []
    shared_dir.mkdir(parents=True, exist_ok=True)

    for relative_path in SEED_FILES:
        target_path = repo_root / relative_path
        shared_path = shared_dir / Path(relative_path).name
        template_path = repo_root / TEMPLATE_RELATIVE_DIR / f"{target_path.stem}.template.csv"

        if target_path.exists() and copy_if_missing(target_path, shared_path):
            messages.append(f"Imported existing local seed into shared store: {shared_path}")

        if not shared_path.exists():
            if not template_path.exists():
                raise FileNotFoundError(
                    f"Missing both shared seed and template for {relative_path}"
                )
            shutil.copy2(template_path, shared_path)
            messages.append(f"Initialized shared seed from template: {shared_path}")

        action = materialize(shared_path, target_path, mode)
        messages.append(f"{action}: {target_path}")

    return messages


def bootstrap_qif_files(repo_root: Path, shared_dir: Path, mode: str) -> list[str]:
    messages: list[str] = []
    shared_dir.mkdir(parents=True, exist_ok=True)
    target_dir = repo_root / QIF_RELATIVE_DIR
    target_dir.mkdir(parents=True, exist_ok=True)

    for target_path in iter_qif_files(target_dir):
        shared_path = shared_dir / target_path.name
        if copy_if_missing(target_path, shared_path):
            messages.append(f"Imported existing local QIF into shared store: {shared_path}")

    shared_qif_files = iter_qif_files(shared_dir)
    for shared_path in shared_qif_files:
        action = materialize(shared_path, target_dir / shared_path.name, mode)
        messages.append(f"{action}: {target_dir / shared_path.name}")

    if not shared_qif_files:
        messages.append(f"No shared QIF files found in {shared_dir}")

    return messages


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--shared-dir",
        help="Override the shared private seed directory.",
    )
    parser.add_argument(
        "--mode",
        choices=["auto", "copy", "hardlink"],
        default="auto",
        help="How to materialize worktree files from the shared seed store.",
    )
    args = parser.parse_args()

    repo_root = Path.cwd()
    shared_dir = resolve_shared_dir(args.shared_dir)
    shared_qif_dir = resolve_shared_qif_dir()
    print(f"Using shared seed directory: {shared_dir}")
    for message in bootstrap_seed_files(repo_root, shared_dir, args.mode):
        print(message)
    print(f"Using shared QIF directory: {shared_qif_dir}")
    for message in bootstrap_qif_files(repo_root, shared_qif_dir, args.mode):
        print(message)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
