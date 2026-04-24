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
from numbers import Number
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


def _serialize_time_bound(value: dt.datetime | str) -> str:
    """Render a Grafana time bound as a query payload string."""
    if isinstance(value, dt.datetime):
        return str(epoch_ms(value))
    return str(value)


def parse_time_picker_ranges(spec: str) -> List[int]:
    """
    Parse a comma-separated list of time-picker ranges into day counts.

    Supports tokens like: 7, 30d, 12w, 6m, 1y.
    """
    tokens = [token.strip().lower() for token in spec.split(",") if token.strip()]
    if not tokens:
        raise ValueError("time picker ranges cannot be empty")

    multipliers = {
        "d": 1,
        "w": 7,
        "m": 30,
        "y": 365,
    }

    parsed: List[int] = []
    for token in tokens:
        match = re.fullmatch(r"(\d+)([dwmy]?)", token)
        if not match:
            raise ValueError(
                f"invalid range token '{token}'. Expected format like 7, 30d, 12w, 6m, 1y."
            )
        value = int(match.group(1))
        suffix = match.group(2) or "d"
        days = value * multipliers[suffix]
        if days <= 0:
            raise ValueError(f"range token '{token}' resolves to non-positive days")
        parsed.append(days)

    # Keep order stable while removing duplicates.
    deduped = list(dict.fromkeys(parsed))
    if not deduped:
        raise ValueError("no valid time picker ranges parsed")
    return deduped


def build_time_windows(range_days: List[int], now_utc: dt.datetime | None = None) -> List[Tuple[str, dt.datetime, dt.datetime]]:
    """Build labelled [from,to] windows anchored to now."""
    now = now_utc or dt.datetime.now(dt.timezone.utc)
    windows = []
    for days in range_days:
        windows.append((f"last_{days}d", now - dt.timedelta(days=days), now))
    return windows


def _slugify_label(label: str) -> str:
    value = re.sub(r"[^a-z0-9]+", "_", label.strip().lower()).strip("_")
    return value or "time_range"


def dashboard_quick_range_windows(dashboard: Dict) -> List[Tuple[str, str, str]]:
    """
    Build labelled windows directly from a dashboard's configured quick ranges.

    Returns tuples of (label_slug, from_expr, to_expr).
    """
    quick_ranges = (dashboard.get("timepicker") or {}).get("quick_ranges") or []
    windows: List[Tuple[str, str, str]] = []
    seen: Set[Tuple[str, str, str]] = set()

    for idx, entry in enumerate(quick_ranges):
        if not isinstance(entry, dict):
            continue
        display = str(entry.get("display", "")).strip()
        from_expr = entry.get("from")
        to_expr = entry.get("to")
        if not isinstance(from_expr, str) or not isinstance(to_expr, str):
            continue
        if not from_expr.strip() or not to_expr.strip():
            continue
        label = _slugify_label(display) if display else f"quick_range_{idx + 1}"
        key = (label, from_expr, to_expr)
        if key in seen:
            continue
        seen.add(key)
        windows.append(key)

    return windows


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
        time_from: dt.datetime | str,
        time_to: dt.datetime | str,
        scoped_vars: Dict,
        ref_id: str = "A",
        format_hint: str | None = None,
    ) -> Dict:
        # PostgreSQL plugin requires string format; DuckDB uses integers.
        _INT_TO_PG_FORMAT = {0: "time_series", 1: "table", 2: "logs"}
        raw_format = format_hint if format_hint is not None else 1
        if datasource.get("type") == "grafana-postgresql-datasource" and isinstance(raw_format, int):
            resolved_format = _INT_TO_PG_FORMAT.get(raw_format, "table")
        else:
            resolved_format = raw_format

        body = {
            "queries": [
                {
                    "datasource": {
                        "type": datasource["type"],
                        "uid": datasource["uid"],
                        "id": datasource["id"],
                    },
                    "datasourceId": datasource["id"],
                    "format": resolved_format,
                    "intervalMs": 60000,
                    "maxDataPoints": 1000,
                    "refId": ref_id,
                    "rawSql": raw_sql,
                    "scopedVars": scoped_vars,
                }
            ],
            "from": _serialize_time_bound(time_from),
            "to": _serialize_time_bound(time_to),
        }
        return self.post("/api/ds/query", body)


def flatten_panels(panels: Iterable[Dict]) -> Iterable[Dict]:
    """Yield all panels, flattening any rows/collapsed children."""
    for panel in panels:
        sub_panels = panel.get("panels") or []
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


_FALLBACK_ONLY_TEXT_VALUES: frozenset[str] = frozenset(
    {
        "none",
        "n/a",
        "no data",
        "no account",
        "no account activity",
        "no transactions need review",
        "no active review queue items",
    }
)


def extract_rows(result: Dict) -> List[Tuple]:
    """Return row tuples from Grafana query result frames/series."""
    rows: List[Tuple] = []

    for frame in result.get("frames") or []:
        values = frame.get("data", {}).get("values") or []
        if not values:
            continue
        rows.extend(tuple(row) for row in zip(*values))

    if rows:
        return rows

    for series in result.get("series", []) or []:
        points = series.get("points", []) or []
        rows.extend(
            tuple(point) if isinstance(point, (list, tuple)) else (point,)
            for point in points
        )

    return rows


def _sql_has_fallback_only_branch(raw_sql: str | None) -> bool:
    if not raw_sql:
        return False
    sql_upper = raw_sql.upper()
    return "UNION ALL" in sql_upper and "WHERE NOT EXISTS" in sql_upper


def _looks_like_zero_text(value: str) -> bool:
    return bool(re.fullmatch(r"0+(?:\.0+)?", value))


def _looks_like_dateish_text(value: str) -> bool:
    return bool(
        re.fullmatch(
            r"\d{4}-\d{2}-\d{2}(?:[ T]\d{2}:\d{2}:\d{2}(?:\.\d+)?)?(?:Z)?",
            value,
        )
    )


def _row_looks_like_fallback_only(row: Tuple) -> bool:
    """
    Heuristic for synthetic placeholder rows appended with `WHERE NOT EXISTS`.

    We treat a row as fallback-only when:
      - it contains at least one explicit placeholder string, and
      - every numeric / boolean field is neutral (0 / False), and
      - all remaining strings are neutral placeholders, blank, zero-like, or date-like.
    """
    saw_placeholder_text = False

    for value in row:
        if value is None:
            continue

        if isinstance(value, bool):
            if value:
                return False
            continue

        if isinstance(value, Number):
            if value != 0:
                return False
            continue

        if isinstance(value, str):
            normalized = value.strip().lower()
            if not normalized:
                continue
            if normalized in _FALLBACK_ONLY_TEXT_VALUES:
                saw_placeholder_text = True
                continue
            if _looks_like_zero_text(normalized) or _looks_like_dateish_text(normalized):
                continue
            return False

        return False

    return saw_placeholder_text


def result_has_values(
    result: Dict,
    min_rows: int,
    raw_sql: str | None = None,
) -> Tuple[bool, str]:
    if "error" in result and result["error"]:
        return False, str(result["error"])

    rows = extract_row_count(result)
    if rows >= min_rows:
        extracted_rows = extract_rows(result)
        if (
            _sql_has_fallback_only_branch(raw_sql)
            and extracted_rows
            and all(_row_looks_like_fallback_only(row) for row in extracted_rows)
        ):
            return False, f"fallback-only ({rows} rows)"
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

    def render_value(var_name: str, fmt: str | None) -> list:
        entry = scoped_vars.get(var_name, {}) or {}
        value = entry.get("value")
        return value if isinstance(value, list) else [value]

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
    time_from: dt.datetime | str,
    time_to: dt.datetime | str,
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
    time_from: dt.datetime | str,
    time_to: dt.datetime | str,
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
    time_from: dt.datetime | str,
    time_to: dt.datetime | str,
    min_rows: int,
    dashboard_data: Dict | None = None,
) -> Tuple[List[Dict], List[Dict]]:
    dashboard = dashboard_data if dashboard_data is not None else client.dashboard(dashboard_meta["uid"])
    scoped_vars = build_scoped_vars(client, dashboard, datasources, time_from, time_to)

    ok_panels: List[Dict] = []
    failing_panels: List[Dict] = []

    for panel in flatten_panels(dashboard.get("panels", [])):
        targets = panel.get("targets") or []
        if not targets:
            continue

        # Resolve panel-level datasource as a fallback for targets that don't
        # specify their own.
        panel_ds = panel.get("datasource") or {}
        panel_ds_uid = panel_ds.get("uid")

        any_target_ok = False
        messages = []
        has_sql_targets = False

        for target in targets:
            raw_sql = target.get("rawSql")
            if not raw_sql:
                continue

            has_sql_targets = True

            # Prefer target-level datasource; fall back to panel-level.
            target_ds = target.get("datasource") or {}
            ds_uid = target_ds.get("uid") or panel_ds_uid
            if not ds_uid or ds_uid not in datasources:
                messages.append(
                    f"{target.get('refId', 'A')}: datasource uid '{ds_uid}' not found"
                )
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
                has_data, msg = result_has_values(result, min_rows, raw_sql=raw_sql)
                messages.append(f"{ref_id}: {msg}")
            except requests.HTTPError as exc:  # pragma: no cover - diagnostic path
                detail = exc.response.text if exc.response is not None else str(exc)
                messages.append(f"{ref_id}: HTTP {exc.response.status_code if exc.response else ''} {detail}")
                has_data = False

            if has_data:
                any_target_ok = True

        if not has_sql_targets:
            continue

        status = {
            "dashboard": dashboard.get("title"),
            "panel_id": panel.get("id"),
            "panel_title": panel.get("title"),
            "messages": "; ".join(messages),
        }

        # Panel passes if at least one SQL target returned data.
        if any_target_ok:
            ok_panels.append(status)
        else:
            failing_panels.append(status)

    return ok_panels, failing_panels


def check_dashboard_across_time_windows(
    client: GrafanaClient,
    dashboard_meta: Dict,
    datasources: Dict[str, Dict],
    time_windows: List[Tuple[str, dt.datetime | str, dt.datetime | str]],
    min_rows: int,
    dashboard_data: Dict | None = None,
) -> Dict:
    """
    Run live panel checks for a dashboard across multiple time-picker windows.

    Returns a dict with aggregated counts and failures by window.
    """
    by_window: List[Dict] = []
    total_ok = 0
    total_fail = 0
    panel_failures_by_window: Dict[Tuple[int | None, str | None], List[Dict]] = {}
    panel_ok_windows: Dict[Tuple[int | None, str | None], Set[str]] = {}
    panel_metadata: Dict[Tuple[int | None, str | None], Dict] = {}

    for label, time_from, time_to in time_windows:
        ok_panels, failing_panels = check_dashboard(
            client=client,
            dashboard_meta=dashboard_meta,
            datasources=datasources,
            time_from=time_from,
            time_to=time_to,
            min_rows=min_rows,
            dashboard_data=dashboard_data,
        )
        for panel in ok_panels:
            key = (panel.get("panel_id"), panel.get("panel_title"))
            panel_metadata.setdefault(
                key,
                {
                    "dashboard": panel.get("dashboard"),
                    "panel_id": panel.get("panel_id"),
                    "panel_title": panel.get("panel_title"),
                },
            )
            panel_ok_windows.setdefault(key, set()).add(label)
        for panel in failing_panels:
            panel["time_window"] = label
            key = (panel.get("panel_id"), panel.get("panel_title"))
            panel_metadata.setdefault(
                key,
                {
                    "dashboard": panel.get("dashboard"),
                    "panel_id": panel.get("panel_id"),
                    "panel_title": panel.get("panel_title"),
                },
            )
            panel_failures_by_window.setdefault(key, []).append(
                {
                    "time_window": label,
                    "messages": panel.get("messages", ""),
                }
            )
        by_window.append(
            {
                "time_window": label,
                "ok_panels": len(ok_panels),
                "failing_panels": failing_panels,
            }
        )
        total_ok += len(ok_panels)
        total_fail += len(failing_panels)

    panels_failing_all_windows: List[Dict] = []
    for key, failures in panel_failures_by_window.items():
        if panel_ok_windows.get(key):
            continue
        meta = panel_metadata.get(
            key,
            {
                "dashboard": dashboard_meta.get("title"),
                "panel_id": key[0],
                "panel_title": key[1],
            },
        )
        combined_messages = "; ".join(
            f"[{failure['time_window']}] {failure['messages']}" for failure in failures
        )
        panels_failing_all_windows.append(
            {
                **meta,
                "messages": combined_messages,
                "failed_time_windows": [failure["time_window"] for failure in failures],
            }
        )

    return {
        "ok_panels": len(panel_ok_windows),
        "failing_panels": len(panels_failing_all_windows),
        "ok_panel_checks": total_ok,
        "failing_panel_checks": total_fail,
        "by_time_window": by_window,
        "panels_failing_all_windows": panels_failing_all_windows,
    }


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
    options = panel.get("options") or {}

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

    # ------------------------------------------------------------------
    # Rule: chart-tooltip-missing
    # Comparison/trend charts should declare tooltip behaviour explicitly so
    # hover detail is predictable instead of relying on plugin defaults.
    # ------------------------------------------------------------------
    if ptype in {"timeseries", "barchart", "piechart", "bargauge"}:
        tooltip = options.get("tooltip")
        if not isinstance(tooltip, dict) or not tooltip.get("mode"):
            add_warning(
                "chart-tooltip-missing",
                "options.tooltip.mode is not set explicitly",
            )

    # ------------------------------------------------------------------
    # Rule: chart-legend-hidden
    # Timeseries and barchart panels should expose series context in the
    # legend instead of hiding it completely.
    # ------------------------------------------------------------------
    if ptype in {"timeseries", "barchart"}:
        legend = options.get("legend")
        if not isinstance(legend, dict):
            add_warning(
                "chart-legend-hidden",
                "options.legend is missing; enable a visible legend for series context",
            )
        elif legend.get("showLegend") is False or legend.get("displayMode") == "hidden":
            add_warning(
                "chart-legend-hidden",
                "options.legend hides series values; use a visible legend",
            )

    # ------------------------------------------------------------------
    # Rule: piechart-value-labels-missing
    # Pie charts must show actual values on-slice or in labels, otherwise the
    # visual encodes share but hides magnitude.
    # ------------------------------------------------------------------
    if ptype == "piechart":
        display_labels = options.get("displayLabels")
        if not isinstance(display_labels, list) or "value" not in display_labels:
            add_warning(
                "piechart-value-labels-missing",
                "options.displayLabels must include 'value'",
            )

    # ------------------------------------------------------------------
    # Rule: bargauge-values-hidden
    # Bargauges should compute values explicitly so the visual exposes the
    # underlying number rather than only a relative bar.
    # ------------------------------------------------------------------
    if ptype == "bargauge":
        reduce_options = options.get("reduceOptions")
        if not isinstance(reduce_options, dict) or reduce_options.get("values") is not True:
            add_warning(
                "bargauge-values-hidden",
                "options.reduceOptions.values must be true",
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
        default=os.environ.get("GRAFANA_ADMIN_USER")
        or ("admin" if os.environ.get("GRAFANA_ADMIN_PASSWORD") else os.environ.get("GRAFANA_USER", "admin")),
        help="Grafana user (used when token is not provided).",
    )
    parser.add_argument(
        "--password",
        default=os.environ.get("GRAFANA_ADMIN_PASSWORD") or os.environ.get("GRAFANA_PASSWORD"),
        help="Grafana password (used when token is not provided).",
    )
    parser.add_argument(
        "--days",
        type=int,
        default=365,
        help=(
            "Legacy single time range (in days). Used only when "
            "--time-picker-ranges is not provided."
        ),
    )
    parser.add_argument(
        "--time-picker-ranges",
        default=os.environ.get("DASHBOARD_TIME_PICKER_RANGES"),
        help=(
            "Comma-separated lookback ranges to validate, e.g. '7,30,90,365' "
            "or '7d,30d,12w'. If omitted, falls back to --days."
        ),
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
            "Defaults to platform/grafana/provisioning/dashboards/ relative to the repo root."
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
    if args.time_picker_ranges:
        try:
            fallback_range_days = parse_time_picker_ranges(args.time_picker_ranges)
        except ValueError as exc:
            print(f"Invalid --time-picker-ranges: {exc}", file=sys.stderr)
            return 2
    else:
        fallback_range_days = [args.days]

    fallback_time_windows = build_time_windows(fallback_range_days)

    use_basic_auth = bool(args.user and args.password)
    client = GrafanaClient(
        base_url=args.base_url,
        token=None if use_basic_auth else args.token,
        user=args.user if use_basic_auth else None,
        password=args.password if use_basic_auth else None,
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
    used_time_window_labels: Set[str] = set()

    json_results: List[Dict] = []

    for dash in dashboards:
        dash_data = client.dashboard(dash["uid"])
        dashboard_windows = dashboard_quick_range_windows(dash_data)
        if dashboard_windows:
            check_windows: List[Tuple[str, dt.datetime | str, dt.datetime | str]] = dashboard_windows
            time_window_source = "dashboard_quick_ranges"
        else:
            check_windows = fallback_time_windows
            time_window_source = "fallback_days"

        used_time_window_labels.update(label for label, _, _ in check_windows)

        time_window_result = check_dashboard_across_time_windows(
            client,
            dash,
            datasources,
            time_windows=check_windows,
            min_rows=args.min_rows,
            dashboard_data=dash_data,
        )
        ok_panels = time_window_result["ok_panels"]
        failing_panels = time_window_result["panels_failing_all_windows"]

        layout_issues: List[Dict] = []
        static_warnings: List[Dict] = []
        parity_warnings: List[Dict] = []

        if not args.no_lint:
            layout_issues = lint_dashboard_titles(
                dash_data,
                max_chars_per_col=args.lint_max_chars_per_col,
                min_chars=args.lint_min_chars,
                text_chars_per_col=args.lint_text_chars_per_col,
                text_height_slack=args.lint_text_height_slack,
            )
            static_warnings = lint_static_dashboard(dash_data)

        if not args.no_parity:
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
                    "ok_panels": ok_panels,
                    "failing_panels": failing_panels,
                    "ok_panel_checks": time_window_result["ok_panel_checks"],
                    "failing_panel_checks": time_window_result["failing_panel_checks"],
                    "time_window_source": time_window_source,
                    "checks_by_time_window": time_window_result["by_time_window"],
                    "layout_lint": layout_issues,
                    "static_warnings": static_warnings,
                    "parity_warnings": parity_warnings,
                }
            )
        else:
            print(
                f"\nDashboard '{dash.get('title')}' ({dash.get('uid')}): "
                f"{ok_panels} panels OK, {len(failing_panels)} failing, "
                f"{len(layout_issues)} layout warnings, "
                f"{len(static_warnings)} static warnings, "
                f"{len(parity_warnings)} parity warnings "
                f"[windows={','.join(label for label, _, _ in check_windows)}]"
            )
            for panel in failing_panels:
                print(
                    f"  - Panel {panel['panel_id']} '{panel['panel_title']}': "
                    f"[{panel.get('time_window', 'unknown')}] {panel['messages']}"
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
            "checked_time_windows": sorted(used_time_window_labels),
            "fallback_time_windows": [window[0] for window in fallback_time_windows],
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
