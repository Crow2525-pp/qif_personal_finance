#!/usr/bin/env python3
"""Stop containers from the legacy project name (qif_personal_finance).

The old underscore-based project name predates the worktree port-isolation
feature.  Containers left running under that name hold the same host ports
the new qif-personal-finance project needs, causing bind failures.
"""

from __future__ import annotations

import subprocess
import sys

LEGACY_PROJECT_NAME = "qif_personal_finance"


def main() -> int:
    result = subprocess.run(
        ["docker", "compose", "--project-name", LEGACY_PROJECT_NAME, "ps", "-q"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0 or not result.stdout.strip():
        return 0

    print(f"Stopping legacy containers (project: {LEGACY_PROJECT_NAME})...")
    subprocess.run(
        ["docker", "compose", "--project-name", LEGACY_PROJECT_NAME, "down"],
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
