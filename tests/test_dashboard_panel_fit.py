import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPTS_DIR = REPO_ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS_DIR))

import check_dashboard_panel_fit as fit  # noqa: E402


# ---------------------------------------------------------------------------
# SQL alias extraction
# ---------------------------------------------------------------------------

def test_extract_quoted_aliases():
    sql = '''SELECT col1 AS "Time Window", col2 AS "Data Through" FROM t'''
    assert fit._extract_select_aliases(sql) == ["Time Window", "Data Through"]


def test_extract_unquoted_aliases():
    sql = "SELECT a AS foo, b AS bar FROM t"
    assert fit._extract_select_aliases(sql) == ["foo", "bar"]


def test_extract_aliases_from_cte():
    sql = (
        "WITH cte AS (SELECT x AS inner_col FROM t) "
        'SELECT cte.inner_col AS "Outer" FROM cte'
    )
    aliases = fit._extract_select_aliases(sql)
    assert "Outer" in aliases


def test_extract_aliases_fallback_comma_count():
    sql = "SELECT 1, 2, 3 FROM t"
    aliases = fit._extract_select_aliases(sql)
    assert len(aliases) == 3


# ---------------------------------------------------------------------------
# Table panel checks
# ---------------------------------------------------------------------------

def _make_table_panel(w, h, sql, show_header=True, panel_id=1, title="Test"):
    return {
        "id": panel_id,
        "title": title,
        "type": "table",
        "gridPos": {"x": 0, "y": 0, "w": w, "h": h},
        "options": {"showHeader": show_header},
        "targets": [{"rawSql": sql, "refId": "A"}],
    }


def test_data_freshness_fails():
    """Data Freshness: w=6, h=3, 3 columns — should fail."""
    panel = _make_table_panel(
        w=6, h=3,
        sql='SELECT a AS "Time Window", b AS "Data Through", c AS "Last Refresh" FROM t',
        title="Data Freshness",
    )
    issues = fit.check_panel_fit(panel)
    assert len(issues) > 0
    rules = {i["rule"] for i in issues}
    assert "table-rows-overflow-height" in rules


def test_executive_summary_passes():
    """Executive Summary: w=18, h=3, 1 column, showHeader=false — should pass."""
    panel = _make_table_panel(
        w=18, h=3,
        sql="SELECT CONCAT('a', 'b') AS summary FROM t",
        show_header=False,
        title="Executive Summary",
    )
    issues = fit.check_panel_fit(panel)
    assert len(issues) == 0


def test_wide_table_passes():
    """Full-width table with plenty of room should pass."""
    panel = _make_table_panel(
        w=24, h=8,
        sql='SELECT a AS "Col1", b AS "Col2" FROM t',
    )
    issues = fit.check_panel_fit(panel)
    assert len(issues) == 0


def test_too_many_columns_for_width():
    """6 columns in w=6 should flag column overflow."""
    cols = ", ".join(f'x AS "Col{i}"' for i in range(6))
    panel = _make_table_panel(w=6, h=8, sql=f"SELECT {cols} FROM t")
    issues = fit.check_panel_fit(panel)
    rules = {i["rule"] for i in issues}
    assert "table-columns-overflow-width" in rules


# ---------------------------------------------------------------------------
# Text panel checks
# ---------------------------------------------------------------------------

def _make_text_panel(w, h, content, panel_id=1, title="Text"):
    return {
        "id": panel_id,
        "title": title,
        "type": "text",
        "gridPos": {"x": 0, "y": 0, "w": w, "h": h},
        "options": {"content": content},
    }


def test_short_text_passes():
    panel = _make_text_panel(w=24, h=8, content="Hello world")
    issues = fit.check_panel_fit(panel)
    assert len(issues) == 0


def test_long_text_fails():
    long_content = "\n".join(["Line " + str(i) for i in range(50)])
    panel = _make_text_panel(w=12, h=4, content=long_content)
    issues = fit.check_panel_fit(panel)
    rules = {i["rule"] for i in issues}
    assert "text-content-overflow-height" in rules


# ---------------------------------------------------------------------------
# Stat panel checks
# ---------------------------------------------------------------------------

def _make_stat_panel(w, h, title="Stat", graph_mode="none", panel_id=1):
    return {
        "id": panel_id,
        "title": title,
        "type": "stat",
        "gridPos": {"x": 0, "y": 0, "w": w, "h": h},
        "options": {"graphMode": graph_mode},
    }


def test_stat_normal_passes():
    panel = _make_stat_panel(w=6, h=4, title="Short")
    issues = fit.check_panel_fit(panel)
    assert len(issues) == 0


def test_stat_very_long_title_fails():
    panel = _make_stat_panel(w=4, h=4, title="A" * 100)
    issues = fit.check_panel_fit(panel)
    rules = {i["rule"] for i in issues}
    assert "stat-title-overflow-width" in rules


# ---------------------------------------------------------------------------
# Integration: real dashboards
# ---------------------------------------------------------------------------

def test_real_dashboards_parse():
    """Smoke test: the script can check all real dashboard files without crashing."""
    dash_dir = REPO_ROOT / "grafana" / "provisioning" / "dashboards"
    if not dash_dir.is_dir():
        return  # skip if dashboards not present
    for fpath in dash_dir.glob("*.json"):
        result = fit.check_dashboard_file(fpath)
        assert "file" in result
        assert "issues" in result
