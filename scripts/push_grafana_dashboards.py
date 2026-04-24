#!/usr/bin/env python3
"""
Push dashboard JSON files into Grafana via API (overwrite).

Usage:
  GRAFANA_URL=http://localhost:3001 \
  GRAFANA_USER=admin GRAFANA_PASSWORD=... \
  python scripts/push_grafana_dashboards.py platform/grafana/provisioning/dashboards/01-executive-overview-mobile.json

If no paths are provided, all *.json files under platform/grafana/provisioning/dashboards are uploaded.
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


def push_dashboard(base_url: str, session: requests.Session, data: dict) -> None:
    payload = {"dashboard": data, "overwrite": True}
    resp = session.post(f"{base_url.rstrip('/')}/api/dashboards/db", json=payload)
    resp.raise_for_status()


def _build_session(user: str, password: str | None, token: str | None) -> requests.Session:
    session = requests.Session()
    if token:
        session.headers["Authorization"] = f"Bearer {token}"
    else:
        session.auth = (user, password)  # type: ignore[assignment]
    return session


def main(argv: List[str]) -> int:
    base_url = os.environ.get("GRAFANA_URL", "http://localhost:3001")
    user = os.environ.get("GRAFANA_USER", "admin")
    password = os.environ.get("GRAFANA_PASSWORD")
    token = os.environ.get("GRAFANA_TOKEN")

    if not token and not password:
        print("Set GRAFANA_PASSWORD or GRAFANA_TOKEN", file=sys.stderr)
        return 1

    session = _build_session(user, password, token)

    targets = argv or glob.glob("platform/grafana/provisioning/dashboards/*.json")
    if not targets:
        print("No dashboard JSON files found.", file=sys.stderr)
        return 1

    for path_str in targets:
        path = Path(path_str)
        if not path.exists():
            print(f"Skipping missing file: {path}", file=sys.stderr)
            continue
        data = load_dashboard(path)
        push_dashboard(base_url, session, data)
        print(f"Pushed {path.name} (uid={data.get('uid')})")

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
