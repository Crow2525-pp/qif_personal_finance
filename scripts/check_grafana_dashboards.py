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
import json
import os
import re
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


def parse_dashboard_number(title: str) -> int | None:
    """Extract numeric dashboard prefix from titles like '02 - Cash Flow Analysis'."""
    if not title:
        return None
    match = re.match(r"^\s*(\d{1,2})\s*-", title)
    if not match:
        return None
    return int(match.group(1))


def parse_range_spec(spec: str) -> Tuple[int, int]:
    """Parse a dashboard range spec like '1-10' or '7'."""
    text = (spec or "").strip()
    if not text:
        raise ValueError("Empty dashboard range")

    if "-" not in text:
        value = int(text)
        return value, value

    start_text, end_text = text.split("-", 1)
    start, end = int(start_text.strip()), int(end_text.strip())
    if end < start:
        raise ValueError(f"Invalid dashboard range '{spec}' (end < start)")
    return start, end


def matches_dashboard_ranges(title: str, ranges: List[Tuple[int, int]]) -> bool:
    """Return True when dashboard title numeric prefix falls in any configured range."""
    number = parse_dashboard_number(title)
    if number is None:
        return False
    return any(start <= number <= end for start, end in ranges)


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


def extract_request_ids(text: str) -> List[str]:
    """Extract Grafana query request identifiers (e.g. SQR113) from text."""
    if not text:
        return []
    ids = re.findall(r"\bSQR\d+\b", text)
    return list(dict.fromkeys(ids))


def compact_error_text(raw_text: str) -> str:
    """Normalize noisy HTTP/API error payloads into a readable single line."""
    text = (raw_text or "").strip()
    if not text:
        return "unknown error"

    try:
        payload = json.loads(text)
        # Typical Grafana error payloads include message/error fields.
        parts = []
        for key in ("message", "error", "status"):
            if key in payload and payload[key]:
                parts.append(str(payload[key]))
        if parts:
            return " | ".join(parts)
    except json.JSONDecodeError:
        pass

    # Strip line breaks to keep panel diagnostics single-line.
    return re.sub(r"\s+", " ", text)


def _quote_sql_value(value) -> str:
    """Return a SQL-safe literal for simple substitutions."""
    if value is None:
        return "NULL"
    if isinstance(value, (int, float)):
        return str(value)
    return "'" + str(value).replace("'", "''") + "'"


def render_sql(raw_sql: str, scoped_vars: Dict) -> str:
    """
    Apply a lightweight variable substitution so API checks behave like Grafana.

    Supports $var, ${var}, and ${var:csv}. Lists are joined with commas.
    """
    raw_sql_text = raw_sql

    def render_value(var_name: str, fmt: str | None) -> str:
        entry = scoped_vars.get(var_name, {}) or {}
        value = entry.get("value")

        values = value if isinstance(value, list) else [value]
        return values

    pattern = re.compile(
        r"\$\{(?P<var>[A-Za-z0-9_]+)(?::(?P<fmt>[A-Za-z0-9_]+))?\}|\$(?P<plain>[A-Za-z0-9_]+)"
    )

    def replacer(match: re.Match) -> str:
        var = match.group("var") or match.group("plain")
        # Preserve Grafana built-in macros like $__timeFrom / $__timeTo.
        # Grafana datasource handles these at execution time.
        if var.startswith("__"):
            return match.group(0)
        fmt = match.group("fmt")
        values = render_value(var, fmt)
        start, end = match.start(), match.end()
        before = raw_sql_text[start - 1 : start] if start > 0 else ""
        after = raw_sql_text[end : end + 1]
        in_quotes = before == "'" and after == "'"

        # Flatten values
        values_list = values if isinstance(values, list) else [values]
        if fmt == "csv":
            if in_quotes:
                return ",".join("" if v is None else str(v) for v in values_list)
            return ",".join(_quote_sql_value(v) for v in values_list if v is not None)

        if in_quotes:
            return "" if values_list[0] is None else str(values_list[0])

        return ",".join(_quote_sql_value(v) for v in values_list if v is not None)

    return pattern.sub(replacer, raw_sql)


def parse_table_alias_map(sql: str) -> Dict[str, str]:
    """
    Build alias->table mapping for schema-qualified FROM/JOIN relations.

    Returns entries where the table is of form schema.table, keyed by alias if
    present, otherwise the table name.
    """
    alias_map: Dict[str, str] = {}
    pattern = re.compile(
        r"\b(?:from|join)\s+([A-Za-z0-9_\.\"']+)(?:\s+(?:as\s+)?([A-Za-z_][A-Za-z0-9_]*))?",
        re.IGNORECASE,
    )
    for table_token, alias in pattern.findall(sql):
        table = table_token.strip().strip('"')
        # Only validate physical relations that are schema-qualified.
        if "." not in table:
            continue
        key = alias or table.split(".")[-1]
        alias_map[key] = table
    return alias_map


def parse_schema_tables(sql: str) -> List[str]:
    """Extract schema-qualified relations used in FROM/JOIN clauses."""
    tables = []
    for table in parse_table_alias_map(sql).values():
        if table not in tables:
            tables.append(table)
    return tables


def parse_alias_column_refs(sql: str, alias_map: Dict[str, str]) -> Dict[str, set]:
    """
    Extract alias.column references and map them to physical schema-qualified tables.
    """
    refs: Dict[str, set] = {}
    pattern = re.compile(r"\b([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\b")
    for alias, col in pattern.findall(sql):
        table = alias_map.get(alias)
        if not table:
            continue
        refs.setdefault(table, set()).add(col)
    return refs


def fetch_table_columns(
    client: GrafanaClient,
    datasource: Dict,
    table: str,
    cache: Dict[str, set],
    time_from: dt.datetime,
    time_to: dt.datetime,
) -> set:
    """Fetch available columns for schema-qualified relation from information_schema."""
    if table in cache:
        return cache[table]

    schema, rel = table.split(".", 1)
    sql = (
        "SELECT column_name "
        "FROM information_schema.columns "
        f"WHERE table_schema = '{schema}' AND table_name = '{rel}' "
        "ORDER BY ordinal_position;"
    )
    response = client.query(
        datasource,
        sql,
        time_from=time_from,
        time_to=time_to,
        scoped_vars={},
        ref_id="SCHEMA",
        format_hint="table",
    )
    result = response.get("results", {}).get("SCHEMA", {})
    if result.get("error"):
        raise ValueError(f"schema lookup failed for {table}: {result.get('error')}")

    columns: set = set()
    for frame in result.get("frames", []) or []:
        values = frame.get("data", {}).get("values") or []
        if not values:
            continue
        # One-column result expected: column_name
        for item in values[0]:
            if item:
                columns.add(str(item))

    cache[table] = columns
    return columns


def validate_sql_schema(
    client: GrafanaClient,
    datasource: Dict,
    sql: str,
    cache: Dict[str, set],
    time_from: dt.datetime,
    time_to: dt.datetime,
) -> Tuple[bool, str]:
    """
    Best-effort schema validation for dashboard SQL.

    Validates existence of schema-qualified FROM/JOIN relations and alias.column
    references bound to those relations.
    """
    alias_map = parse_table_alias_map(sql)
    tables = parse_schema_tables(sql)
    if not tables:
        return True, "schema validation skipped (no schema-qualified relations)"

    missing_tables: List[str] = []
    missing_cols: List[str] = []

    for table in tables:
        cols = fetch_table_columns(
            client,
            datasource,
            table,
            cache=cache,
            time_from=time_from,
            time_to=time_to,
        )
        if not cols:
            missing_tables.append(table)

    if missing_tables:
        return False, "missing tables: " + ", ".join(missing_tables)

    refs = parse_alias_column_refs(sql, alias_map)
    for table, referenced in refs.items():
        available = cache.get(table, set())
        for col in sorted(referenced):
            if col not in available:
                missing_cols.append(f"{table}.{col}")

    if missing_cols:
        return False, "missing columns: " + ", ".join(missing_cols)

    return True, "schema ok"


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
    schema_validate: bool,
    schema_cache: Dict[str, set],
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
        target_diagnostics: List[Dict] = []
        panel_request_ids: List[str] = []

        for target in targets:
            raw_sql = target.get("rawSql")
            if not raw_sql:
                continue

            format_hint = target.get("format")
            ref_id = target.get("refId", "A")

            try:
                rendered_sql = render_sql(raw_sql, scoped_vars)
                if schema_validate:
                    schema_ok, schema_msg = validate_sql_schema(
                        client,
                        datasources[ds_uid],
                        rendered_sql,
                        cache=schema_cache,
                        time_from=time_from,
                        time_to=time_to,
                    )
                    if not schema_ok:
                        has_data = False
                        messages.append(f"{ref_id}: schema {schema_msg}")
                        target_diagnostics.append(
                            {
                                "ref_id": ref_id,
                                "status": "schema_error",
                                "message": schema_msg,
                                "request_ids": [],
                            }
                        )
                        continue

                query_response = client.query(
                    datasources[ds_uid],
                    rendered_sql,
                    time_from=time_from,
                    time_to=time_to,
                    scoped_vars=scoped_vars,
                    ref_id=ref_id,
                    format_hint=format_hint,
                )
                result = query_response.get("results", {}).get(ref_id, {})
                has_data, msg = result_has_values(result, min_rows)
                messages.append(f"{ref_id}: {msg}")
                request_ids = extract_request_ids(msg)
                panel_request_ids.extend(request_ids)
                target_diagnostics.append(
                    {
                        "ref_id": ref_id,
                        "status": "ok" if has_data else "no_data_or_error",
                        "message": msg,
                        "request_ids": request_ids,
                    }
                )
            except requests.HTTPError as exc:  # pragma: no cover - diagnostic path
                detail = exc.response.text if exc.response is not None else str(exc)
                compact = compact_error_text(detail)
                request_ids = extract_request_ids(compact)
                panel_request_ids.extend(request_ids)
                messages.append(
                    f"{ref_id}: HTTP {exc.response.status_code if exc.response else ''} {compact}"
                )
                target_diagnostics.append(
                    {
                        "ref_id": ref_id,
                        "status": "http_error",
                        "message": compact,
                        "request_ids": request_ids,
                    }
                )
                has_data = False

            if has_data:
                panel_ok = True
                break

        panel_request_ids = list(dict.fromkeys(panel_request_ids))
        status = {
            "dashboard": dashboard.get("title"),
            "panel_id": panel.get("id"),
            "panel_title": panel.get("title"),
            "messages": "; ".join(messages),
            "request_ids": panel_request_ids,
            "target_diagnostics": target_diagnostics,
        }

        if panel_ok:
            ok_panels.append(status)
        else:
            failing_panels.append(status)

    return ok_panels, failing_panels


def lint_dashboard_titles(
    dashboard: Dict,
    max_chars_per_col: int,
    min_chars: int,
    text_chars_per_col: float,
    text_height_slack: int,
) -> List[Dict]:
    """Heuristic lint: flag titles that likely overflow their panel width."""
    issues: List[Dict] = []

    for panel in flatten_panels(dashboard.get("panels", [])):
        title = panel.get("title") or ""
        if not title:
            continue

        grid = panel.get("gridPos") or {}
        width = grid.get("w", 24)
        height = grid.get("h", 1)

        # Title width heuristic
        allowed = max(min_chars, width * max_chars_per_col)
        if len(title) > allowed:
            issues.append(
                {
                    "panel_id": panel.get("id"),
                    "panel_title": title,
                    "width": width,
                    "title_len": len(title),
                    "allowed": allowed,
                }
            )

        # Text panel content height heuristic
        if panel.get("type") == "text":
            content = (panel.get("options") or {}).get("content", "")
            if isinstance(content, str) and content.strip():
                chars_per_row = max(1, int(width * text_chars_per_col))
                est_lines = (len(content) // chars_per_row) + 1
                allowed_lines = height + text_height_slack
                if est_lines > allowed_lines:
                    issues.append(
                        {
                            "panel_id": panel.get("id"),
                            "panel_title": title,
                            "width": width,
                            "height": height,
                            "content_len": len(content),
                            "est_lines": est_lines,
                            "allowed_lines": allowed_lines,
                            "message": "text likely overflows box",
                        }
                    )
    return issues


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
        "--dashboard-range",
        action="append",
        default=[],
        help=(
            "Dashboard numeric range filter based on title prefix, e.g. "
            "'1-10', '11-23', or '7'. Can be set multiple times."
        ),
    )
    parser.add_argument(
        "--min-rows",
        type=int,
        default=1,
        help="Minimum number of rows/points expected for a panel.",
    )
    parser.add_argument(
        "--no-lint",
        action="store_true",
        help="Skip layout linting (e.g., long titles vs. panel width).",
    )
    parser.add_argument(
        "--schema-validate",
        action="store_true",
        help=(
            "Validate schema-qualified table/column references against "
            "information_schema before running panel queries."
        ),
    )
    parser.add_argument(
        "--lint-max-chars-per-col",
        type=int,
        default=5,
        help="Heuristic: max characters per grid column before flagging a title (default: 5).",
    )
    parser.add_argument(
        "--lint-min-chars",
        type=int,
        default=20,
        help="Minimum title length threshold even for small panels (default: 20).",
    )
    parser.add_argument(
        "--lint-text-chars-per-col",
        type=float,
        default=1.5,
        help="Heuristic chars per grid column for text panels (default: 1.5).",
    )
    parser.add_argument(
        "--lint-text-height-slack",
        type=int,
        default=0,
        help="Extra grid rows tolerated for text panels before flagging (default: 0).",
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

    if args.dashboard_range:
        ranges: List[Tuple[int, int]] = []
        try:
            ranges = [parse_range_spec(spec) for spec in args.dashboard_range]
        except ValueError as exc:
            print(f"Invalid --dashboard-range value: {exc}", file=sys.stderr)
            return 1
        dashboards = [
            d for d in dashboards if matches_dashboard_ranges(d.get("title", ""), ranges)
        ]

    if not dashboards:
        print("No dashboards found matching the provided filters.", file=sys.stderr)
        return 1

    total_failures = 0
    total_lint = 0
    schema_cache: Dict[str, set] = {}
    for dash in dashboards:
        ok_panels, failing_panels = check_dashboard(
            client,
            dash,
            datasources,
            time_from=time_from,
            time_to=time_to,
            min_rows=args.min_rows,
            schema_validate=args.schema_validate,
            schema_cache=schema_cache,
        )

        lint_issues: List[Dict] = []
        if not args.no_lint:
            lint_issues = lint_dashboard_titles(
                client.dashboard(dash["uid"]),
                max_chars_per_col=args.lint_max_chars_per_col,
                min_chars=args.lint_min_chars,
                text_chars_per_col=args.lint_text_chars_per_col,
                text_height_slack=args.lint_text_height_slack,
            )

        print(
            f"\nDashboard '{dash.get('title')}' ({dash.get('uid')}): "
            f"{len(ok_panels)} panels OK, {len(failing_panels)} failing, "
            f"{len(lint_issues)} lint warnings"
        )
        for panel in failing_panels:
            total_failures += 1
            req = (
                f" [requestIds: {', '.join(panel['request_ids'])}]"
                if panel.get("request_ids")
                else ""
            )
            print(
                f"  - Panel {panel['panel_id']} '{panel['panel_title']}': "
                f"{panel['messages']}{req}"
            )
            for target in panel.get("target_diagnostics", []):
                print(
                    f"      ref {target.get('ref_id')}: {target.get('status')} - {target.get('message')}"
                )
        for issue in lint_issues:
            total_lint += 1
            title_len = issue.get("title_len") or issue.get("content_len")
            allowed = issue.get("allowed") or issue.get("allowed_lines")
            extra = ""
            if issue.get("message"):
                extra = f" ({issue['message']})"
            print(
                f"  - LINT Panel {issue.get('panel_id')} '{issue.get('panel_title')}' "
                f"len={title_len} allowed~{allowed} (w={issue.get('width')}, h={issue.get('height')}){extra}"
            )

    if total_failures or total_lint:
        print(
            f"\nFAIL: {total_failures} panels returned no data or errors; "
            f"{total_lint} lint warnings."
        )
        return 2

    print("\nAll panels returned data (no lint warnings).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
