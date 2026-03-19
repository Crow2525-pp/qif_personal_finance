#!/usr/bin/env python3
"""Bootstrap private dbt seed files for this worktree from a shared local store."""

from __future__ import annotations

import argparse
import hashlib
import os
import shutil
from pathlib import Path


SEED_FILES = [
    "pipeline_personal_finance/dbt_finance/seeds/known_values.csv",
    "pipeline_personal_finance/dbt_finance/seeds/mortgage_patch_data.csv",
    "pipeline_personal_finance/dbt_finance/seeds/property_assets.csv",
    "pipeline_personal_finance/dbt_finance/seeds/property_valuation_overrides.csv",
    "pipeline_personal_finance/dbt_finance/seeds/recommendation_outcomes.csv",
]


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def resolve_shared_dir(cli_value: str | None) -> Path:
    if cli_value:
        return Path(cli_value).expanduser().resolve()
    env_value = os.getenv("QIF_SHARED_SEED_DIR")
    if env_value:
        return Path(env_value).expanduser().resolve()
    return (Path.home() / ".qif_personal_finance" / "shared_seeds").resolve()


def ensure_parent(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)


def copy_if_missing(source: Path, destination: Path) -> bool:
    if destination.exists():
        return False
    ensure_parent(destination)
    shutil.copy2(source, destination)
    return True


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


def bootstrap(repo_root: Path, shared_dir: Path, mode: str) -> list[str]:
    messages: list[str] = []
    shared_dir.mkdir(parents=True, exist_ok=True)

    for relative_path in SEED_FILES:
        target_path = repo_root / relative_path
        shared_path = shared_dir / Path(relative_path).name
        template_path = target_path.with_suffix(".template.csv")

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
    print(f"Using shared seed directory: {shared_dir}")
    for message in bootstrap(repo_root, shared_dir, args.mode):
        print(message)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
