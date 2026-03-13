import datetime as dt
from pathlib import Path
import sys


REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = REPO_ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS_DIR))

import check_grafana_dashboards as checker  # noqa: E402


def test_parse_time_picker_ranges_accepts_multiple_suffixes():
    assert checker.parse_time_picker_ranges("7,30d,12w,6m,1y") == [7, 30, 84, 180, 365]


def test_parse_time_picker_ranges_dedupes_and_preserves_order():
    assert checker.parse_time_picker_ranges("30,7,30d,7d,365") == [30, 7, 365]


def test_parse_time_picker_ranges_rejects_invalid_tokens():
    try:
        checker.parse_time_picker_ranges("7,thirty")
        assert False, "expected ValueError for invalid token"
    except ValueError as exc:
        assert "invalid range token" in str(exc)


def test_build_time_windows_uses_shared_end_timestamp():
    now = dt.datetime(2026, 3, 3, 12, 0, tzinfo=dt.timezone.utc)
    windows = checker.build_time_windows([7, 30], now_utc=now)
    assert [w[0] for w in windows] == ["last_7d", "last_30d"]
    assert windows[0][2] == now
    assert windows[1][2] == now
    assert windows[0][1] == now - dt.timedelta(days=7)
    assert windows[1][1] == now - dt.timedelta(days=30)


def test_dashboard_quick_range_windows_extracts_configured_presets():
    dashboard = {
        "timepicker": {
            "quick_ranges": [
                {"display": "Last complete month", "from": "now-1M/M", "to": "now/M"},
                {"display": "Year to date", "from": "now/y", "to": "now"},
                {"display": "Trailing 12 months", "from": "now-12M/M", "to": "now/M"},
            ]
        }
    }
    assert checker.dashboard_quick_range_windows(dashboard) == [
        ("last_complete_month", "now-1M/M", "now/M"),
        ("year_to_date", "now/y", "now"),
        ("trailing_12_months", "now-12M/M", "now/M"),
    ]


def test_dashboard_quick_range_windows_skips_invalid_entries():
    dashboard = {
        "timepicker": {
            "quick_ranges": [
                {"display": "Bad", "from": None, "to": "now"},
                "not-an-object",
                {"display": "", "from": "now-30d", "to": "now"},
            ]
        }
    }
    assert checker.dashboard_quick_range_windows(dashboard) == [
        ("quick_range_3", "now-30d", "now")
    ]


# ---------------------------------------------------------------------------
# check_dashboard: target-level datasource resolution and pass semantics
# ---------------------------------------------------------------------------

class _FakeClient:
    """Minimal stub for GrafanaClient used in check_dashboard tests."""

    def __init__(self, datasources, query_results=None):
        self._datasources = datasources
        self._query_results = query_results or {}

    def datasources(self):
        return self._datasources

    def dashboard(self, uid):
        return {}

    def query(self, datasource, raw_sql, **kwargs):
        ref_id = kwargs.get("ref_id", "A")
        key = (datasource["uid"], ref_id)
        if key in self._query_results:
            return self._query_results[key]
        # Default: return one row
        return {
            "results": {
                ref_id: {
                    "frames": [{"data": {"values": [["row1"]]}}]
                }
            }
        }


def _make_dashboard(panels):
    return {"title": "test", "panels": panels, "templating": {"list": []}}


def test_check_dashboard_panel_passes_if_any_target_has_data():
    """Panel with two targets should pass if at least one returns data."""
    ds = {"pg": {"uid": "pg", "type": "postgres", "id": 1}}
    # Target A returns data, Target B is empty
    results = {
        ("pg", "A"): {"results": {"A": {"frames": [{"data": {"values": [["v"]]}}]}}},
        ("pg", "B"): {"results": {"B": {"frames": [{"data": {"values": [[]]}}]}}},
    }
    client = _FakeClient(ds, results)
    dashboard = _make_dashboard([
        {
            "id": 1,
            "title": "Mixed",
            "datasource": {"uid": "pg"},
            "targets": [
                {"refId": "A", "rawSql": "SELECT 1"},
                {"refId": "B", "rawSql": "SELECT 1"},
            ],
        }
    ])
    ok, fail = checker.check_dashboard(
        client, {"uid": "x"}, ds,
        time_from="now-1d", time_to="now", min_rows=1,
        dashboard_data=dashboard,
    )
    assert len(ok) == 1 and len(fail) == 0, "panel should pass when any target has data"


def test_check_dashboard_panel_fails_when_all_targets_empty():
    """Panel should fail only when every target is empty."""
    ds = {"pg": {"uid": "pg", "type": "postgres", "id": 1}}
    results = {
        ("pg", "A"): {"results": {"A": {"frames": [{"data": {"values": [[]]}}]}}},
        ("pg", "B"): {"results": {"B": {"frames": [{"data": {"values": [[]]}}]}}},
    }
    client = _FakeClient(ds, results)
    dashboard = _make_dashboard([
        {
            "id": 1,
            "title": "AllEmpty",
            "datasource": {"uid": "pg"},
            "targets": [
                {"refId": "A", "rawSql": "SELECT 1"},
                {"refId": "B", "rawSql": "SELECT 1"},
            ],
        }
    ])
    ok, fail = checker.check_dashboard(
        client, {"uid": "x"}, ds,
        time_from="now-1d", time_to="now", min_rows=1,
        dashboard_data=dashboard,
    )
    assert len(fail) == 1 and len(ok) == 0, "panel should fail when all targets empty"


def test_check_dashboard_resolves_target_level_datasource():
    """Target-level datasource should take precedence over panel-level."""
    ds = {
        "pg": {"uid": "pg", "type": "postgres", "id": 1},
        "duck": {"uid": "duck", "type": "duckdb", "id": 2},
    }
    # Only the duckdb datasource returns data
    results = {
        ("pg", "A"): {"results": {"A": {"frames": [{"data": {"values": [[]]}}]}}},
        ("duck", "B"): {"results": {"B": {"frames": [{"data": {"values": [["v"]]}}]}}},
    }
    client = _FakeClient(ds, results)
    dashboard = _make_dashboard([
        {
            "id": 1,
            "title": "TargetDS",
            "datasource": {"uid": "pg"},
            "targets": [
                {"refId": "A", "rawSql": "SELECT 1"},
                {"refId": "B", "rawSql": "SELECT 1", "datasource": {"uid": "duck"}},
            ],
        }
    ])
    ok, fail = checker.check_dashboard(
        client, {"uid": "x"}, ds,
        time_from="now-1d", time_to="now", min_rows=1,
        dashboard_data=dashboard,
    )
    # Target B used duckdb and returned data, so panel passes
    assert len(ok) == 1 and len(fail) == 0


def test_check_dashboard_missing_ds_does_not_block_other_targets():
    """A target with an unknown datasource should not fail the whole panel
    if another target succeeds."""
    ds = {"pg": {"uid": "pg", "type": "postgres", "id": 1}}
    client = _FakeClient(ds)
    dashboard = _make_dashboard([
        {
            "id": 1,
            "title": "MixedDS",
            "datasource": {"uid": "pg"},
            "targets": [
                {"refId": "A", "rawSql": "SELECT 1"},
                {"refId": "B", "rawSql": "SELECT 1", "datasource": {"uid": "gone"}},
            ],
        }
    ])
    ok, fail = checker.check_dashboard(
        client, {"uid": "x"}, ds,
        time_from="now-1d", time_to="now", min_rows=1,
        dashboard_data=dashboard,
    )
    assert len(ok) == 1, "panel should pass — target A succeeded"
