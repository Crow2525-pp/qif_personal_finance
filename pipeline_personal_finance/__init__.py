"""Package exports for Dagster code locations.

Keep imports lazy so tooling and unit tests can import the package without
triggering dbt parsing at module import time.
"""

from __future__ import annotations


def __getattr__(name: str):
    if name == "defs":
        from .definitions import defs

        return defs
    if name == "dbt_manifest_path":
        from .constants import dbt_manifest_path

        return dbt_manifest_path
    raise AttributeError(name)


__all__ = ["defs", "dbt_manifest_path"]
