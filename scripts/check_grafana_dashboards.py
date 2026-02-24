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

Static lint checks (run without Grafana connectivity):
    python scripts/check_grafana_dashboards.py --lint-only

JSON output for CI:
    python scripts/check_grafana_dashboards.py --json
"""

from __future__ import annotations

import argparse
import datetime as dt
import json as _json_mod
import os
import re
import sys
from typing import Dict, Iterable, List, Set, Tuple

import requests

# On Windows the default console encoding is often cp1252, which cannot
# represent the emoji characters that appear in some dashboard titles.
# Reconfigure stdout/stderr to UTF-8 with replacement so the script never
# crashes mid-output.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[union-attr]
if hasattr(sys.stderr, "reconfigure"):
    sys.stderr.reconfigure(encoding="utf-8", errors="replace")  # type: ignore[union-attr]


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
        fmt = match.group("fmt")

        # Leave unknown variables untouched so the Grafana API can resolve
        # its own built-ins ($__timeFrom, $__timeTo, $__timeFilter, etc.)
        if var not in scoped_vars:
            return match.group(0)

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

    try:
        query_result = client.query(
            datasources[ds_uid],
            raw_sql,
            time_from=time_from,
            time_to=time_to,
            scoped_vars={},
            ref_id="Var",
        )
    except requests.HTTPError:
        return []

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
                rendered_sql = render_sql(raw_sql, scoped_vars)
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


# ---------------------------------------------------------------------------
# Static lint checks (no Grafana connectivity required)
# ---------------------------------------------------------------------------

#: Panel types that honour the global time picker.  SQL panels of any other
#: type silently ignore it, which is what we want to flag.
_TIMEPICKER_AWARE_TYPES: Set[str] = {"timeseries", "graph", "logs"}

#: Currency unit values that are broken in Grafana 12 and should use 'short'
#: (or no unit) instead.
_BROKEN_CURRENCY_UNITS: Set[str] = {"currencyAUD", "currencyUSD", "currencyGBP", "currencyEUR"}


def _iter_unit_values(panel: Dict) -> Iterable[Tuple[str, str]]:
    """
    Yield (location_label, unit_string) for every unit setting in a panel.

    Covers fieldConfig.defaults.unit and all unit override properties.
    """
    fc = panel.get("fieldConfig") or {}
    defaults = fc.get("defaults") or {}
    unit = defaults.get("unit")
    if unit:
        yield "fieldConfig.defaults", unit

    for ov in fc.get("overrides") or []:
        matcher = (ov.get("matcher") or {}).get("options", "override")
        for prop in ov.get("properties") or []:
            if prop.get("id") == "unit":
                yield f"override({matcher})", prop.get("value", "")


def lint_static_panel(panel: Dict) -> List[Dict]:
    """
    Run static (offline) lint rules against a single panel.

    Returns a list of warning dicts, each with keys:
        rule, panel_id, panel_title, detail
    """
    warnings: List[Dict] = []
    seen: Set[Tuple] = set()

    pid = panel.get("id")
    ptitle = panel.get("title", "")
    ptype = panel.get("type", "")
    fc = panel.get("fieldConfig") or {}
    defaults = fc.get("defaults") or {}

    def add_warning(rule: str, detail: str) -> None:
        key = (rule, pid, detail)
        if key in seen:
            return
        seen.add(key)
        warnings.append(
            {
                "rule": rule,
                "panel_id": pid,
                "panel_title": ptitle,
                "panel_type": ptype,
                "detail": detail,
            }
        )

    # ------------------------------------------------------------------
    # Rule: currency-unit
    # currencyAUD / currencyUSD (and similar) units are broken in Grafana 12.
    # Recommend using 'short' or leaving the unit empty.
    # ------------------------------------------------------------------
    for location, unit_val in _iter_unit_values(panel):
        if unit_val in _BROKEN_CURRENCY_UNITS:
            add_warning(
                "currency-unit",
                f"Unit '{unit_val}' at {location} — use 'short' unit instead "
                f"(currency units broken in Grafana 12)",
            )

    # ------------------------------------------------------------------
    # Rule: current-date-timepicker
    # stat / gauge / table panels that contain CURRENT_DATE or NOW() in their
    # SQL queries are anchored to wall-clock time and ignore the dashboard
    # time picker.  This is often unintentional.
    # ------------------------------------------------------------------
    if ptype not in _TIMEPICKER_AWARE_TYPES:
        for target in panel.get("targets") or []:
            sql = target.get("rawSql") or ""
            sql_upper = sql.upper()
            if "CURRENT_DATE" in sql_upper or "NOW()" in sql_upper:
                ref_id = target.get("refId", "A")
                add_warning(
                    "current-date-timepicker",
                    f"Target {ref_id}: SQL uses CURRENT_DATE/NOW() in a "
                    f"'{ptype}' panel — panel ignores the time picker",
                )
                break  # one warning per panel is enough

    # ------------------------------------------------------------------
    # Rule: percentunit-missing-bounds
    # percentunit fields without explicit min and max can render confusingly
    # when values fall outside the 0-1 range (e.g., negative savings rates).
    # ------------------------------------------------------------------
    default_unit = defaults.get("unit", "")
    if default_unit == "percentunit":
        missing = []
        if "min" not in defaults:
            missing.append("min")
        if "max" not in defaults:
            missing.append("max")
        if missing:
            add_warning(
                "percentunit-missing-bounds",
                f"fieldConfig.defaults.unit is 'percentunit' but "
                f"{' and '.join(missing)} are not set — add explicit bounds "
                f"(e.g. min=-1, max=1 if negatives are possible)",
            )

    return warnings


def lint_static_dashboard(dashboard: Dict) -> List[Dict]:
    """
    Run all static lint rules across every panel in a dashboard.

    Warnings are deduplicated: the same (rule, panel_id, detail) triple
    is reported only once even if detected through multiple code paths.
    """
    all_warnings: List[Dict] = []
    seen: Set[Tuple] = set()

    for panel in flatten_panels(dashboard.get("panels", [])):
        for w in lint_static_panel(panel):
            key = (w["rule"], w["panel_id"], w["detail"])
            if key not in seen:
                seen.add(key)
                all_warnings.append(w)

    return all_warnings


def lint_dashboard_files(dashboard_dir: str) -> Dict[str, List[Dict]]:
    """
    Load every *.json file in dashboard_dir and run static lint.

    Returns a mapping of filename -> list of warning dicts.
    Files that cannot be parsed are reported as a single parse-error warning.
    """
    results: Dict[str, List[Dict]] = {}
    try:
        filenames = sorted(
            f for f in os.listdir(dashboard_dir)
            if f.endswith(".json") and not f.endswith(".pre_update")
        )
    except OSError:
        return results

    for fname in filenames:
        fpath = os.path.join(dashboard_dir, fname)
        try:
            with open(fpath, encoding="utf-8", errors="replace") as fh:
                dashboard = _json_mod.load(fh)
        except Exception as exc:
            results[fname] = [
                {
                    "rule": "parse-error",
                    "panel_id": None,
                    "panel_title": None,
                    "panel_type": None,
                    "detail": f"Could not parse JSON: {exc}",
                }
            ]
            continue

        results[fname] = lint_static_dashboard(dashboard)

    return results


# ---------------------------------------------------------------------------
# Layout lint (existing)
# ---------------------------------------------------------------------------


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


# ---------------------------------------------------------------------------
# Parity checks: mobile dashboards must not use currency units
# ---------------------------------------------------------------------------

#: Forbidden currency unit values that should not appear on mobile dashboards.
FORBIDDEN_CURRENCY_UNITS: frozenset = frozenset(
    {"currencyUSD", "currencyAUD", "currencyGBP", "currencyEUR"}
)

#: Title substrings that identify a dashboard as mobile.
MOBILE_TITLE_MARKERS: tuple = ("mobile", "📱")


def _is_mobile_dashboard(title: str) -> bool:
    """Return True if the dashboard title looks like a mobile dashboard."""
    lower = title.lower()
    return any(marker in lower for marker in MOBILE_TITLE_MARKERS)


def _collect_panel_units(panel: Dict) -> List[str]:
    """Return all unit values present in a panel's fieldConfig (defaults + overrides)."""
    units: List[str] = []
    fc = panel.get("fieldConfig") or {}

    default_unit = (fc.get("defaults") or {}).get("unit")
    if default_unit:
        units.append(default_unit)

    for override in fc.get("overrides") or []:
        for prop in override.get("properties") or []:
            if prop.get("id") == "unit":
                value = prop.get("value")
                if value:
                    units.append(value)

    return units


def lint_mobile_parity(dashboard: Dict) -> List[Dict]:
    """
    Scan a mobile dashboard for currency-unit violations.

    Returns a list of warning dicts (one per offending panel/unit combination).
    Each dict contains keys: panel_id, panel_title, unit, severity='WARNING'.
    """
    warnings: List[Dict] = []
    title = dashboard.get("title", "")

    if not _is_mobile_dashboard(title):
        return warnings

    for panel in flatten_panels(dashboard.get("panels", [])):
        units = _collect_panel_units(panel)
        for unit in units:
            if unit in FORBIDDEN_CURRENCY_UNITS:
                warnings.append(
                    {
                        "panel_id": panel.get("id"),
                        "panel_title": panel.get("title", ""),
                        "unit": unit,
                        "severity": "WARNING",
                        "message": (
                            f"mobile panel uses forbidden currency unit '{unit}'; "
                            "use 'short' for monetary values per project convention"
                        ),
                    }
                )

    return warnings


# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Check Grafana dashboards for empty panels and static configuration issues."
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
    parser.add_argument(
        "--no-lint",
        action="store_true",
        help="Skip all lint checks (layout and static).",
    )
    parser.add_argument(
        "--lint-only",
        action="store_true",
        help=(
            "Run only static lint checks against dashboard JSON files on disk. "
            "No Grafana connectivity is required."
        ),
    )
    parser.add_argument(
        "--dashboard-dir",
        default=os.environ.get(
            "DASHBOARD_DIR",
            os.path.join(
                os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                "grafana",
                "provisioning",
                "dashboards",
            ),
        ),
        help=(
            "Directory containing dashboard JSON files for static lint. "
            "Defaults to grafana/provisioning/dashboards/ relative to the repo root."
        ),
    )
    parser.add_argument(
        "--no-parity",
        action="store_true",
        help="Skip mobile/desktop KPI parity checks (currency unit validation).",
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
    parser.add_argument(
        "--json",
        action="store_true",
        dest="json_output",
        help="Emit a machine-readable JSON summary to stdout instead of human text.",
    )
    return parser.parse_args()


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------


def main() -> int:
    args = parse_args()

    # ------------------------------------------------------------------
    # Lint-only mode: scan files on disk, no Grafana connection needed.
    # ------------------------------------------------------------------
    if args.lint_only:
        file_warnings = lint_dashboard_files(args.dashboard_dir)
        total_warnings = sum(len(ws) for ws in file_warnings.values())
        has_errors = any(
            w["rule"] == "parse-error"
            for ws in file_warnings.values()
            for w in ws
        )

        if args.json_output:
            summary = {
                "mode": "lint-only",
                "dashboard_dir": args.dashboard_dir,
                "total_warnings": total_warnings,
                "has_errors": has_errors,
                "files": {
                    fname: warnings
                    for fname, warnings in sorted(file_warnings.items())
                },
            }
            print(_json_mod.dumps(summary, indent=2))
        else:
            for fname, warnings in sorted(file_warnings.items()):
                if not warnings:
                    continue
                print(f"\n{fname}: {len(warnings)} warning(s)")
                for w in warnings:
                    pid_label = f"panel {w['panel_id']}" if w["panel_id"] is not None else "file"
                    print(f"  [{w['rule']}] {pid_label} '{w['panel_title']}': {w['detail']}")

            if total_warnings:
                print(f"\nWARN: {total_warnings} static lint warning(s) across {len(file_warnings)} file(s).")
            else:
                print("\nAll dashboard files passed static lint.")

        # parse-errors are hard failures; warnings are not (exit 0)
        return 1 if has_errors else 0

    # ------------------------------------------------------------------
    # Normal mode: connect to Grafana, check live panels, run lint.
    # ------------------------------------------------------------------
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
    total_layout_lint = 0
    total_static_lint = 0
    total_parity_warnings = 0

    json_results: List[Dict] = []

    for dash in dashboards:
        ok_panels, failing_panels = check_dashboard(
            client,
            dash,
            datasources,
            time_from=time_from,
            time_to=time_to,
            min_rows=args.min_rows,
        )

        layout_issues: List[Dict] = []
        static_warnings: List[Dict] = []
        parity_warnings: List[Dict] = []

        dash_data: Dict | None = None
        if not args.no_lint or not args.no_parity:
            dash_data = client.dashboard(dash["uid"])

        if not args.no_lint and dash_data is not None:
            layout_issues = lint_dashboard_titles(
                dash_data,
                max_chars_per_col=args.lint_max_chars_per_col,
                min_chars=args.lint_min_chars,
                text_chars_per_col=args.lint_text_chars_per_col,
                text_height_slack=args.lint_text_height_slack,
            )
            static_warnings = lint_static_dashboard(dash_data)

        if not args.no_parity and dash_data is not None:
            parity_warnings = lint_mobile_parity(dash_data)

        total_failures += len(failing_panels)
        total_layout_lint += len(layout_issues)
        total_static_lint += len(static_warnings)
        total_parity_warnings += len(parity_warnings)

        if args.json_output:
            json_results.append(
                {
                    "dashboard": dash.get("title"),
                    "uid": dash.get("uid"),
                    "ok_panels": len(ok_panels),
                    "failing_panels": failing_panels,
                    "layout_lint": layout_issues,
                    "static_warnings": static_warnings,
                    "parity_warnings": parity_warnings,
                }
            )
        else:
            print(
                f"\nDashboard '{dash.get('title')}' ({dash.get('uid')}): "
                f"{len(ok_panels)} panels OK, {len(failing_panels)} failing, "
                f"{len(layout_issues)} layout warnings, "
                f"{len(static_warnings)} static warnings, "
                f"{len(parity_warnings)} parity warnings"
            )
            for panel in failing_panels:
                print(
                    f"  - Panel {panel['panel_id']} '{panel['panel_title']}': "
                    f"{panel['messages']}"
                )
            for issue in layout_issues:
                title_len = issue.get("title_len") or issue.get("content_len")
                allowed = issue.get("allowed") or issue.get("allowed_lines")
                extra = ""
                if issue.get("message"):
                    extra = f" ({issue['message']})"
                print(
                    f"  - LAYOUT Panel {issue.get('panel_id')} '{issue.get('panel_title')}' "
                    f"len={title_len} allowed~{allowed} (w={issue.get('width')}, h={issue.get('height')}){extra}"
                )
            for warning in static_warnings:
                print(
                    f"  - WARN [{warning['rule']}] Panel {warning['panel_id']} "
                    f"'{warning['panel_title']}' ({warning['panel_type']}): {warning['detail']}"
                )
            for warning in parity_warnings:
                print(
                    f"  - PARITY Panel {warning['panel_id']} '{warning['panel_title']}': "
                    f"{warning['message']}"
                )

    if args.json_output:
        summary = {
            "total_failing_panels": total_failures,
            "total_layout_warnings": total_layout_lint,
            "total_static_warnings": total_static_lint,
            "total_parity_warnings": total_parity_warnings,
            "passed": total_failures == 0,
            "dashboards": json_results,
        }
        print(_json_mod.dumps(summary, indent=2))
    else:
        if total_failures:
            print(
                f"\nFAIL: {total_failures} panels returned no data or errors; "
                f"{total_layout_lint} layout warnings; "
                f"{total_static_lint} static lint warnings; "
                f"{total_parity_warnings} parity warnings."
            )
        elif total_layout_lint or total_static_lint or total_parity_warnings:
            print(
                f"\nWARN: All panels returned data. "
                f"{total_layout_lint} layout warnings; "
                f"{total_static_lint} static lint warnings; "
                f"{total_parity_warnings} parity warnings."
            )
        else:
            print("\nAll panels returned data (no lint warnings).")

    return 1 if total_failures else 0


if __name__ == "__main__":
    sys.exit(main())
