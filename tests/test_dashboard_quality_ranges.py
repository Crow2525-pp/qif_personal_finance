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
