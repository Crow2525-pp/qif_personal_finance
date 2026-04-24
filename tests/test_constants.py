from __future__ import annotations

from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

import pytest

from pipeline_personal_finance.constants import (
    parse_project_on_load_enabled,
    resolve_dbt_manifest_path,
)


def test_parse_project_on_load_enabled_truthy_and_falsey_values():
    assert parse_project_on_load_enabled("true") is True
    assert parse_project_on_load_enabled("On") is True
    assert parse_project_on_load_enabled("0") is False
    assert parse_project_on_load_enabled("") is False


def test_resolve_dbt_manifest_path_uses_existing_manifest_without_parsing(
    tmp_path: Path,
):
    project_dir = tmp_path / "dbt_project"
    target_dir = project_dir / "target"
    manifest_path = target_dir / "manifest.json"
    manifest_path.parent.mkdir(parents=True)
    manifest_path.write_text("{}", encoding="utf-8")

    ensure_seed_stubs = Mock()
    resource_factory = Mock()

    resolved = resolve_dbt_manifest_path(
        project_dir=project_dir,
        target_dir=target_dir,
        parse_on_load=False,
        resource_factory=resource_factory,
        ensure_seed_stubs=ensure_seed_stubs,
    )

    assert resolved == manifest_path
    ensure_seed_stubs.assert_not_called()
    resource_factory.assert_not_called()


def test_resolve_dbt_manifest_path_defers_to_dagster_when_parse_on_load_disabled(
    tmp_path: Path,
):
    project_dir = tmp_path / "dbt_project"
    target_dir = project_dir / "target"
    manifest_path = target_dir / "manifest.json"

    ensure_seed_stubs = Mock()
    resource_factory = Mock()

    resolved = resolve_dbt_manifest_path(
        project_dir=project_dir,
        target_dir=target_dir,
        parse_on_load=False,
        resource_factory=resource_factory,
        ensure_seed_stubs=ensure_seed_stubs,
    )

    assert resolved == manifest_path
    ensure_seed_stubs.assert_not_called()
    resource_factory.assert_not_called()


def test_resolve_dbt_manifest_path_regenerates_manifest_when_enabled_and_missing(
    tmp_path: Path,
):
    project_dir = tmp_path / "dbt_project"
    target_dir = project_dir / "target"
    manifest_path = target_dir / "manifest.json"

    ensure_seed_stubs = Mock()
    cli_result = SimpleNamespace(target_path=target_dir)
    cli_invocation = Mock()
    cli_invocation.wait.return_value = cli_result
    dbt_resource = Mock()
    dbt_resource.cli.return_value = cli_invocation
    resource_factory = Mock(return_value=dbt_resource)

    resolved = resolve_dbt_manifest_path(
        project_dir=project_dir,
        target_dir=target_dir,
        parse_on_load=True,
        resource_factory=resource_factory,
        ensure_seed_stubs=ensure_seed_stubs,
    )

    assert resolved == manifest_path
    ensure_seed_stubs.assert_called_once_with()
    resource_factory.assert_called_once_with(project_dir)
    dbt_resource.cli.assert_called_once_with(["--quiet", "parse"], target_path=target_dir)
    cli_invocation.wait.assert_called_once_with()


def test_resolve_dbt_manifest_path_raises_helpful_error_when_dbt_cli_missing(
    tmp_path: Path,
):
    project_dir = tmp_path / "dbt_project"
    target_dir = project_dir / "target"

    ensure_seed_stubs = Mock()
    cli_invocation = Mock()
    cli_invocation.wait.side_effect = FileNotFoundError("dbt")
    dbt_resource = Mock()
    dbt_resource.cli.return_value = cli_invocation
    resource_factory = Mock(return_value=dbt_resource)

    with pytest.raises(RuntimeError, match=r"dbt manifest not found") as exc:
        resolve_dbt_manifest_path(
            project_dir=project_dir,
            target_dir=target_dir,
            parse_on_load=True,
            resource_factory=resource_factory,
            ensure_seed_stubs=ensure_seed_stubs,
        )

    assert "dbt deps" in str(exc.value)
    ensure_seed_stubs.assert_called_once_with()
