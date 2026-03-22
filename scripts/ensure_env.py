#!/usr/bin/env python3
"""Ensure .env exists and contains all keys from .env.template.

Copies .env.template to .env if missing, then appends any keys present
in .env.template but absent from .env.  Prints a warning for each added key.
"""

from __future__ import annotations

import re
import shutil
from pathlib import Path


def main() -> int:
    env_path = Path(".env")
    template_path = Path(".env.template")

    if not template_path.exists():
        return 0

    if not env_path.exists():
        shutil.copy(template_path, env_path)
        print("WARNING: .env not found — created from .env.template with placeholder values.")
        print("         Edit .env and replace CHANGE_ME_* values before services can start correctly.")
        return 0

    env_text = env_path.read_text(encoding="utf-8")
    template_text = template_path.read_text(encoding="utf-8")

    existing_keys = set(re.findall(r"^([A-Z][A-Z0-9_]*)=", env_text, re.MULTILINE))
    missing = [
        line
        for line in template_text.splitlines()
        if line and not line.startswith("#") and line.split("=")[0] not in existing_keys
    ]

    if missing:
        with env_path.open("a", encoding="utf-8") as f:
            f.write("\n# Added from .env.template\n")
            f.write("\n".join(missing) + "\n")
        print("  INFO: Added missing keys from .env.template — check/update values in .env:")
        for line in missing:
            print(f"    {line.split('=')[0]}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
