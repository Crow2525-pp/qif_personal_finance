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
            # JSON parseability is covered by a separate linter gate.
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


def test_executive_dashboard_removes_dashboard_period_variable():
    dashboard = _load_dashboard("executive-dashboard.json")
    assert _get_template_var(dashboard, "dashboard_period") is None


def test_executive_dashboard_links_do_not_forward_dashboard_period():
    dashboard = _load_dashboard("executive-dashboard.json")
    urls = list(_collect_urls(dashboard))
    assert all("var-dashboard_period=" not in url for url in urls)


def test_savings_dashboard_uses_canonical_time_window_labels():
    dashboard = _load_dashboard("savings-analysis-dashboard.json")
    time_window = _get_template_var(dashboard, "time_window")

    assert time_window is not None
    assert [o.get("text") for o in time_window.get("options", [])] == [
        "Last Complete Month",
        "Year to Date",
        "Trailing 12 Months",
    ]


def test_rollout_uses_metadata_tags_instead_of_hardcoded_lists():
    tranche_a = []
    tranche_b = []

    for filename, dashboard in _all_dashboards():
        tags = set(dashboard.get("tags", []))
        if "time_control_rollout:tranche_a" in tags:
            tranche_a.append(filename)
        if "time_control_rollout:tranche_b" in tags:
            tranche_b.append(filename)

    assert tranche_a, "Expected at least one dashboard tagged time_control_rollout:tranche_a"
    assert tranche_b, "Expected at least one dashboard tagged time_control_rollout:tranche_b"
