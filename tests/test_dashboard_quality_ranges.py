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
