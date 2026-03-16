import json
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DASHBOARD_DIR = REPO_ROOT / "grafana" / "provisioning" / "dashboards"
RECENCY_PANEL_TITLES = {"Data Freshness", "Last Completed Month"}


def test_every_dashboard_has_last_completed_month_message():
    dashboard_files = sorted(DASHBOARD_DIR.glob("*.json"))
    assert dashboard_files, "Expected provisioned Grafana dashboards to be present."

    missing = []

    for dashboard_file in dashboard_files:
        dashboard = json.loads(dashboard_file.read_text(encoding="utf-8"))
        panel_titles = {
            panel.get("title")
            for panel in dashboard.get("panels", [])
            if isinstance(panel, dict)
        }
        if RECENCY_PANEL_TITLES.isdisjoint(panel_titles):
            missing.append(dashboard_file.name)

    assert not missing, (
        "Dashboards missing last-completed-month messaging: "
        + ", ".join(missing)
    )
