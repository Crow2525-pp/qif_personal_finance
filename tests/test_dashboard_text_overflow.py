import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = REPO_ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS_DIR))

import check_dashboard_text_overflow as overflow  # noqa: E402


def test_panel_allows_scroll_marker():
    panel = {
        "description": (
            "Intentionally scrollable documentation panel. "
            f"{overflow.OVERFLOW_POLICY_ALLOW_SCROLL_MARKER}"
        )
    }
    assert overflow._panel_allows_scroll(panel)


def test_panel_without_marker_does_not_allow_scroll():
    assert not overflow._panel_allows_scroll({"description": "Normal panel"})
    assert not overflow._panel_allows_scroll({})
