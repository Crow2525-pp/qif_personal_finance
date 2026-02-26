import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DASHBOARD_DIR = REPO_ROOT / "grafana" / "provisioning" / "dashboards"


def _load_dashboard(filename: str) -> dict:
    with open(DASHBOARD_DIR / filename, "r", encoding="utf-8") as f:
        return json.load(f)


def _all_dashboards():
    for path in sorted(DASHBOARD_DIR.glob("*.json")):
        try:
            yield path.name, _load_dashboard(path.name)
        except json.JSONDecodeError:
            continue


def _get_template_var(dashboard: dict, var_name: str) -> dict | None:
    for var in dashboard.get("templating", {}).get("list", []):
        if var.get("name") == var_name:
            return var
    return None


def _collect_urls(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "url" and isinstance(value, str):
                yield value
            else:
                yield from _collect_urls(value)
    elif isinstance(node, list):
        for item in node:
            yield from _collect_urls(item)


EXCEPTION_TAGS = {
    "time_control:time_specific_exception",
    "time_control:no_time_component_exception",
    "time_control:forward_looking_exception",
    "time_control:hybrid_future_component_exception",
}


def _get_archetype(dashboard: dict) -> str | None:
    for tag in dashboard.get("tags", []):
        if isinstance(tag, str) and tag.startswith("time_control_archetype:"):
            return tag.split(":", 1)[1]
    return None


def _is_exception_dashboard(dashboard: dict) -> bool:
    tags = set(dashboard.get("tags", []))
    return bool(tags & EXCEPTION_TAGS)


# --- Tests ---


def test_no_dashboard_has_time_window_variable():
    """No dashboard should have a time_window template variable."""
    for filename, dashboard in _all_dashboards():
        assert _get_template_var(dashboard, "time_window") is None, (
            f"{filename} still has time_window template variable"
        )


def test_no_dashboard_has_dashboard_period_variable():
    """No dashboard should have a dashboard_period template variable."""
    for filename, dashboard in _all_dashboards():
        assert _get_template_var(dashboard, "dashboard_period") is None, (
            f"{filename} still has dashboard_period template variable"
        )


def test_no_links_contain_var_time_window():
    """No dashboard links should reference var-time_window."""
    for filename, dashboard in _all_dashboards():
        urls = list(_collect_urls(dashboard))
        for url in urls:
            assert "var-time_window" not in url, (
                f"{filename} has link with var-time_window: {url}"
            )


def test_no_links_contain_var_dashboard_period():
    """No dashboard links should reference var-dashboard_period."""
    for filename, dashboard in _all_dashboards():
        urls = list(_collect_urls(dashboard))
        for url in urls:
            assert "var-dashboard_period" not in url, (
                f"{filename} has link with var-dashboard_period: {url}"
            )


def test_historical_windowed_dashboards_have_quick_ranges():
    """Historical windowed dashboards must have 3 canonical quick_ranges presets."""
    expected_displays = {"Last complete month", "Year to date", "Trailing 12 months"}
    for filename, dashboard in _all_dashboards():
        if _get_archetype(dashboard) != "historical_windowed":
            continue
        timepicker = dashboard.get("timepicker", {})
        quick_ranges = timepicker.get("quick_ranges", [])
        displays = {qr.get("display", "") for qr in quick_ranges if isinstance(qr, dict)}
        assert expected_displays <= displays, (
            f"{filename} missing quick_ranges: {expected_displays - displays}"
        )


def test_atemporal_dashboards_have_hidden_timepicker():
    """Atemporal dashboards must have timepicker.hidden = true."""
    for filename, dashboard in _all_dashboards():
        if _get_archetype(dashboard) != "atemporal_no_time_component":
            continue
        timepicker = dashboard.get("timepicker", {})
        assert timepicker.get("hidden") is True, (
            f"{filename} (atemporal) must have timepicker.hidden = true"
        )


def test_every_dashboard_has_archetype_tag():
    """Every dashboard must have exactly one archetype tag."""
    valid = {
        "time_control_archetype:historical_windowed",
        "time_control_archetype:historical_fixed_period",
        "time_control_archetype:atemporal_no_time_component",
        "time_control_archetype:forward_looking",
        "time_control_archetype:hybrid_past_future",
    }
    for filename, dashboard in _all_dashboards():
        tags = [t for t in dashboard.get("tags", []) if isinstance(t, str)]
        archetype_tags = [t for t in tags if t.startswith("time_control_archetype:")]
        assert len(archetype_tags) == 1, (
            f"{filename} must have exactly one archetype tag, found {archetype_tags}"
        )
        assert archetype_tags[0] in valid, (
            f"{filename} has invalid archetype tag: {archetype_tags[0]}"
        )


def test_exception_dashboards_have_reason_tag():
    """Exception dashboards must have a time_control_reason:* tag."""
    for filename, dashboard in _all_dashboards():
        if not _is_exception_dashboard(dashboard):
            continue
        tags = [t for t in dashboard.get("tags", []) if isinstance(t, str)]
        reason_tags = [t for t in tags if t.startswith("time_control_reason:")]
        assert reason_tags, (
            f"{filename} (exception) must have a time_control_reason:* tag"
        )


def test_executive_dashboard_sql_uses_time_macros():
    """The executive dashboard should use $__timeFrom/$__timeTo in SQL."""
    dashboard = _load_dashboard("executive-dashboard.json")
    panels = dashboard.get("panels", [])
    sql_texts = []
    for panel in panels:
        for target in panel.get("targets", []):
            if isinstance(target, dict) and "rawSql" in target:
                sql_texts.append(target["rawSql"])
    assert sql_texts, "executive dashboard should have panel SQL"
    macro_count = sum(
        1 for sql in sql_texts
        if "$__timeFrom" in sql or "$__timeTo" in sql or "$__timeFilter" in sql
    )
    assert macro_count > 0, (
        "executive dashboard must reference time macros in at least one panel query"
    )
