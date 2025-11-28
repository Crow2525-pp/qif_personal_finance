#!/usr/bin/env python3
"""
Check that Grafana dashboards return data for each panel.

The script calls the Grafana HTTP API, executes every SQL target in each
dashboard, and reports panels that come back empty or with errors. It is
intended to be run after loading/reloading dashboards to ensure they are
actually showing values.

Usage example:
    GRAFANA_URL=http://localhost:3001 \\
    GRAFANA_TOKEN=eyJrIjoi... \\
    python scripts/check_grafana_dashboards.py --days 90

If you cannot use an API token, set GRAFANA_USER and GRAFANA_PASSWORD
instead. The script exits with a non-zero status when any panel is empty
or errors so it can be wired into CI or a post-provision hook.
"""

from __future__ import annotations

import argparse
import datetime as dt
import os
import sys
from typing import Dict, Iterable, List, Tuple

import requests


def epoch_ms(value: dt.datetime) -> int:
    """Convert a timezone-aware datetime to epoch milliseconds."""
    return int(value.timestamp() * 1000)


class GrafanaClient:
    """Small wrapper around the Grafana HTTP API."""

    def __init__(
        self,
        base_url: str,
        token: str | None,
        user: str | None,
        password: str | None,
        timeout: int = 15,
    ) -> None:
        if not token and not (user and password):
            raise ValueError(
                "Provide either GRAFANA_TOKEN or both GRAFANA_USER and GRAFANA_PASSWORD"
            )

        self.base_url = base_url.rstrip("/")
        self.timeout = timeout

        session = requests.Session()
        session.headers.update({"Accept": "application/json"})

        if token:
            session.headers["Authorization"] = f"Bearer {token}"
        else:
            session.auth = (user, password)  # type: ignore[arg-type]

        self.session = session

    def get(self, path: str) -> Dict:
        response = self.session.get(f"{self.base_url}{path}", timeout=self.timeout)
        response.raise_for_status()
        return response.json()

    def post(self, path: str, payload: Dict) -> Dict:
        response = self.session.post(
            f"{self.base_url}{path}", json=payload, timeout=self.timeout
        )
        response.raise_for_status()
        return response.json()

    def datasources(self) -> Dict[str, Dict]:
        return {ds["uid"]: ds for ds in self.get("/api/datasources")}

    def search_dashboards(self) -> List[Dict]:
        return self.get("/api/search?type=dash-db")

    def dashboard(self, uid: str) -> Dict:
        data = self.get(f"/api/dashboards/uid/{uid}")
        return data["dashboard"]

    def query(
        self,
        datasource: Dict,
        raw_sql: str,
        time_from: dt.datetime,
        time_to: dt.datetime,
        scoped_vars: Dict,
        ref_id: str = "A",
        format_hint: str | None = None,
    ) -> Dict:
        body = {
            "queries": [
                {
                    "datasource": {
                        "type": datasource["type"],
                        "uid": datasource["uid"],
                        "id": datasource["id"],
                    },
                    "datasourceId": datasource["id"],
                    "format": format_hint or "table",
                    "intervalMs": 60000,
                    "maxDataPoints": 1000,
                    "refId": ref_id,
                    "rawSql": raw_sql,
                    "scopedVars": scoped_vars,
                }
            ],
            "from": str(epoch_ms(time_from)),
            "to": str(epoch_ms(time_to)),
        }
        return self.post("/api/ds/query", body)


def flatten_panels(panels: Iterable[Dict]) -> Iterable[Dict]:
    """Yield all panels, flattening any rows/collapsed children."""
    for panel in panels:
        sub_panels = panel.get("panels") or panel.get("collapsed") or []
        if sub_panels:
            yield from flatten_panels(sub_panels)
        else:
            yield panel


def extract_row_count(result: Dict) -> int:
    """Return number of rows/points from a Grafana query result."""
    total = 0
    frames = result.get("frames") or []
    for frame in frames:
        values = frame.get("data", {}).get("values") or []
        if values:
            total += len(values[0])

    # Older format fallback
    if total == 0:
        for series in result.get("series", []) or []:
            total += len(series.get("points", []))

    return total


def result_has_values(result: Dict, min_rows: int) -> Tuple[bool, str]:
    if "error" in result and result["error"]:
        return False, str(result["error"])

    rows = extract_row_count(result)
    if rows >= min_rows:
        return True, f"{rows} rows"

    return False, f"empty ({rows} rows)"


def resolve_variable_options(
    client: GrafanaClient,
    var_def: Dict,
    datasources: Dict[str, Dict],
    time_from: dt.datetime,
    time_to: dt.datetime,
) -> List:
    """Execute a templating query variable to collect its option values."""
    if var_def.get("type") != "query":
        return []

    ds_info = var_def.get("datasource") or {}
    ds_uid = ds_info.get("uid")
    if not ds_uid or ds_uid not in datasources:
        return []

    raw_sql = var_def.get("definition") or var_def.get("query") or ""
    if not raw_sql.strip():
        return []

    query_result = client.query(
        datasources[ds_uid],
        raw_sql,
        time_from=time_from,
        time_to=time_to,
        scoped_vars={},
        ref_id="Var",
    )
    results = query_result.get("results", {})
    first = results.get("Var") or {}
    frames = first.get("frames") or []
    values: List = []

    for frame in frames:
        data_values = frame.get("data", {}).get("values") or []
        if not data_values:
            continue

        for row in zip(*data_values):
            values.append(row[0])

    return values


def build_scoped_vars(
    client: GrafanaClient,
    dashboard: Dict,
    datasources: Dict[str, Dict],
    time_from: dt.datetime,
    time_to: dt.datetime,
) -> Dict:
    scoped = {}
    for var in dashboard.get("templating", {}).get("list", []):
        if var.get("hide") == 2:  # hidden custom/constant
            continue

        options = resolve_variable_options(client, var, datasources, time_from, time_to)

        value = var.get("current", {}).get("value")
        if value == "$__all" and options:
            value = options
        elif value in (None, [], "$__all") and options:
            value = options

        scoped[var["name"]] = {
            "text": var.get("current", {}).get("text", value),
            "value": value if value is not None else options,
            "selected": var.get("current", {}).get("selected", True),
        }
    return scoped


def check_dashboard(
    client: GrafanaClient,
    dashboard_meta: Dict,
    datasources: Dict[str, Dict],
    time_from: dt.datetime,
    time_to: dt.datetime,
    min_rows: int,
) -> Tuple[List[Dict], List[Dict]]:
    dashboard = client.dashboard(dashboard_meta["uid"])
    scoped_vars = build_scoped_vars(client, dashboard, datasources, time_from, time_to)

    ok_panels: List[Dict] = []
    failing_panels: List[Dict] = []

    for panel in flatten_panels(dashboard.get("panels", [])):
        targets = panel.get("targets") or []
        if not targets:
            continue

        datasource = panel.get("datasource") or {}
        ds_uid = datasource.get("uid")
        if not ds_uid or ds_uid not in datasources:
            continue

        panel_ok = False
        messages = []

        for target in targets:
            raw_sql = target.get("rawSql")
            if not raw_sql:
                continue

            format_hint = target.get("format")
            ref_id = target.get("refId", "A")

            try:
                query_response = client.query(
                    datasources[ds_uid],
                    raw_sql,
                    time_from=time_from,
                    time_to=time_to,
                    scoped_vars=scoped_vars,
                    ref_id=ref_id,
                    format_hint=format_hint,
                )
                result = query_response.get("results", {}).get(ref_id, {})
                has_data, msg = result_has_values(result, min_rows)
                messages.append(f"{ref_id}: {msg}")
            except requests.HTTPError as exc:  # pragma: no cover - diagnostic path
                detail = exc.response.text if exc.response is not None else str(exc)
                messages.append(f"{ref_id}: HTTP {exc.response.status_code if exc.response else ''} {detail}")
                has_data = False

            if has_data:
                panel_ok = True
                break

        status = {
            "dashboard": dashboard.get("title"),
            "panel_id": panel.get("id"),
            "panel_title": panel.get("title"),
            "messages": "; ".join(messages),
        }

        if panel_ok:
            ok_panels.append(status)
        else:
            failing_panels.append(status)

    return ok_panels, failing_panels


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check Grafana dashboards for empty panels."
    )
    parser.add_argument(
        "--base-url",
        default=os.environ.get("GRAFANA_URL", "http://localhost:3001"),
        help="Grafana base URL (default: http://localhost:3001)",
    )
    parser.add_argument(
        "--token",
        default=os.environ.get("GRAFANA_TOKEN"),
        help="Grafana API token (alternatively set GRAFANA_USER/PASSWORD).",
    )
    parser.add_argument(
        "--user",
        default=os.environ.get("GRAFANA_USER", "admin"),
        help="Grafana user (used when token is not provided).",
    )
    parser.add_argument(
        "--password",
        default=os.environ.get("GRAFANA_PASSWORD"),
        help="Grafana password (used when token is not provided).",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=365,
        help="Time range to query backwards from now (in days). Default: 365.",
    )
    parser.add_argument(
        "--dashboard",
        action="append",
        default=[],
        help="Dashboard title or UID to include (can be set multiple times).",
    )
    parser.add_argument(
        "--min-rows",
        type=int,
        default=1,
        help="Minimum number of rows/points expected for a panel.",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    time_to = dt.datetime.now(dt.timezone.utc)
    time_from = time_to - dt.timedelta(days=args.days)

    client = GrafanaClient(
        base_url=args.base_url,
        token=args.token,
        user=args.user,
        password=args.password,
    )

    datasources = client.datasources()
    dashboards = client.search_dashboards()

    if args.dashboard:
        wanted = {item.lower() for item in args.dashboard}

        def keep(item: Dict) -> bool:
            uid = item.get("uid", "").lower()
            title = item.get("title", "").lower()
            return any(selector in (uid, title) for selector in wanted) or any(
                selector in title for selector in wanted
            )

        dashboards = [d for d in dashboards if keep(d)]

    if not dashboards:
        print("No dashboards found matching the provided filters.", file=sys.stderr)
        return 1

    total_failures = 0
    for dash in dashboards:
        ok_panels, failing_panels = check_dashboard(
            client,
            dash,
            datasources,
            time_from=time_from,
            time_to=time_to,
            min_rows=args.min_rows,
        )

        print(
            f"\nDashboard '{dash.get('title')}' ({dash.get('uid')}): "
            f"{len(ok_panels)} panels OK, {len(failing_panels)} failing"
        )
        for panel in failing_panels:
            total_failures += 1
            print(
                f"  - Panel {panel['panel_id']} '{panel['panel_title']}': "
                f"{panel['messages']}"
            )

    if total_failures:
        print(f"\nFAIL: {total_failures} panels returned no data or errors.")
        return 2

    print("\nAll panels returned data.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
