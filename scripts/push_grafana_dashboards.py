#!/usr/bin/env python3
"""
Push dashboard JSON files into Grafana via API (overwrite).

Usage:
  GRAFANA_URL=http://localhost:3001 \
  GRAFANA_USER=admin GRAFANA_PASSWORD=... \
  python scripts/push_grafana_dashboards.py grafana/provisioning/dashboards/01-executive-overview-mobile.json

If no paths are provided, all *.json files under grafana/provisioning/dashboards are uploaded.
"""

from __future__ import annotations

import glob
import json
import os
import sys
from pathlib import Path
from typing import List

import requests


def load_dashboard(path: Path) -> dict:
    with path.open() as f:
        return json.load(f)


def push_dashboard(base_url: str, auth: tuple[str, str] | None, data: dict) -> None:
    payload = {"dashboard": data, "overwrite": True}
    resp = requests.post(f"{base_url.rstrip('/')}/api/dashboards/db", json=payload, auth=auth)
    resp.raise_for_status()


def main(argv: List[str]) -> int:
    base_url = os.environ.get("GRAFANA_URL", "http://localhost:3001")
    user = os.environ.get("GRAFANA_USER", "admin")
    password = os.environ.get("GRAFANA_PASSWORD")
    token = os.environ.get("GRAFANA_TOKEN")

    if token:
        auth = None
        headers = {"Authorization": f"Bearer {token}"}
        requests.defaults.headers.update(headers)  # type: ignore[attr-defined]
    else:
        if not password:
            print("Set GRAFANA_PASSWORD or GRAFANA_TOKEN", file=sys.stderr)
            return 1
        auth = (user, password)

    targets = argv or glob.glob("grafana/provisioning/dashboards/*.json")
    if not targets:
        print("No dashboard JSON files found.", file=sys.stderr)
        return 1

    for path_str in targets:
        path = Path(path_str)
        if not path.exists():
            print(f"Skipping missing file: {path}", file=sys.stderr)
            continue
        data = load_dashboard(path)
        push_dashboard(base_url, auth, data)
        print(f"Pushed {path.name} (uid={data.get('uid')})")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
