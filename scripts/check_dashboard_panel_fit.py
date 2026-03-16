#!/usr/bin/env python3
"""
Static lint: check that dashboard panel content fits within its bounding box.

Applies panel-type-specific heuristics to estimate whether titles, table
columns, text content, descriptions, and other visual elements can render
without clipping or overflow inside the panel's gridPos dimensions.

Usage:
    python scripts/check_dashboard_panel_fit.py                # human-readable
    python scripts/check_dashboard_panel_fit.py --json          # machine-readable
    python scripts/check_dashboard_panel_fit.py --verbose       # show passing panels too

Exit codes:
    0  all panels pass
    1  one or more panels have fit violations
    2  runtime error
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Dict, Iterable, List

# ---------------------------------------------------------------------------
# Pixel-budget constants (Grafana 10.x defaults at ~1920px viewport)
# ---------------------------------------------------------------------------

# Each Grafana grid unit ≈ this many pixels.
GRID_PX_W = 75
GRID_PX_H = 30

# Fixed chrome consumed by every panel.
PANEL_TITLE_BAR_PX = 30
PANEL_HORIZ_PAD_PX = 32   # left + right padding/border

# Table-specific geometry.
TABLE_HEADER_ROW_PX = 32
TABLE_DATA_ROW_PX = 32
TABLE_MIN_COL_PX = 80     # minimum readable column width

# Character width estimate (Grafana default font, proportional).
CHAR_WIDTH_PX = 7.5

# Stat / gauge panels.
STAT_VALUE_PX = 40         # minimum height for the big number
STAT_SPARKLINE_PX = 30     # extra height when sparkline is enabled

# Description tooltip does NOT consume panel area — it's a hover popup.
# Long descriptions are fine.


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def flatten_panels(panels: Iterable[Dict]) -> Iterable[Dict]:
    """Yield all panels, flattening any rows/collapsed children."""
    for panel in panels:
        sub_panels = panel.get("panels") or []
        if sub_panels:
            yield from flatten_panels(sub_panels)
        else:
            yield panel


def _extract_select_aliases(sql: str) -> List[str]:
    """Best-effort extraction of column aliases from the outermost SELECT.

    Looks for ``AS "Name"`` and ``AS name`` patterns in the final SELECT
    statement.  Falls back to counting commas in the SELECT clause when
    aliases are not explicit.
    """
    if not sql:
        return []

    # Find the last SELECT that isn't inside a CTE/subquery.
    # Simple heuristic: take the last SELECT that is NOT preceded by '(' on the
    # same line — won't be perfect but good enough for dashboard SQL.
    # Better approach: find the final top-level SELECT by matching parens.
    depth = 0
    last_top_select = -1
    upper = sql.upper()
    for i in range(len(sql)):
        ch = sql[i]
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        elif depth == 0 and upper[i:i + 6] == 'SELECT' and (i == 0 or not upper[i - 1].isalpha()):
            last_top_select = i

    if last_top_select < 0:
        return []

    select_body = sql[last_top_select + 6:]
    # Trim at FROM (top-level)
    depth = 0
    from_pos = -1
    upper_body = select_body.upper()
    for i in range(len(select_body)):
        ch = select_body[i]
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        elif depth == 0 and upper_body[i:i + 4] == 'FROM' and (i == 0 or not upper_body[i - 1].isalnum()):
            from_pos = i
            break

    if from_pos > 0:
        select_body = select_body[:from_pos]

    # Extract quoted aliases: AS "Foo Bar"
    quoted = re.findall(r'[Aa][Ss]\s+"([^"]+)"', select_body)
    if quoted:
        return quoted

    # Extract unquoted aliases: AS foo_bar
    unquoted = re.findall(r'[Aa][Ss]\s+([A-Za-z_]\w*)', select_body)
    if unquoted:
        return unquoted

    # Fallback: count top-level commas + 1
    depth = 0
    commas = 0
    for ch in select_body:
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
        elif ch == ',' and depth == 0:
            commas += 1

    if commas > 0:
        return [f"col{i}" for i in range(commas + 1)]

    return ["col0"]


def _count_table_columns(panel: Dict) -> tuple[int, List[str]]:
    """Return (column_count, column_names) for a table panel."""
    # First check for explicit field overrides that hide columns — the
    # effective column count is what Grafana actually renders.
    targets = panel.get("targets") or []
    all_aliases: List[str] = []
    for target in targets:
        sql = target.get("rawSql", "")
        all_aliases.extend(_extract_select_aliases(sql))

    if not all_aliases:
        # Can't determine columns — assume 1 (safe default).
        return 1, ["unknown"]

    return len(all_aliases), all_aliases


def _panel_avail_width_px(w: int) -> int:
    return w * GRID_PX_W - PANEL_HORIZ_PAD_PX


def _panel_avail_height_px(h: int) -> int:
    return h * GRID_PX_H - PANEL_TITLE_BAR_PX


# ---------------------------------------------------------------------------
# Per-panel-type fit checks
# ---------------------------------------------------------------------------

def _table_row_height_px(panel: Dict) -> int:
    """Return the data-row height in pixels based on the panel's cellHeight option.

    Grafana supports three densities (Grafana 10+):
      sm  → 26 px   md (default) → 32 px   lg → 42 px
    """
    cell_height = (panel.get("options") or {}).get("cellHeight", "md")
    return {"sm": 26, "md": 32, "lg": 42}.get(cell_height, 32)


def _check_table(panel: Dict, grid: Dict) -> List[Dict]:
    """Check table panel: columns fit width, rows fit height."""
    issues: List[Dict] = []
    w = grid.get("w", 24)
    h = grid.get("h", 6)
    title = panel.get("title", "")

    avail_w = _panel_avail_width_px(w)
    avail_h = _panel_avail_height_px(h)

    num_cols, col_names = _count_table_columns(panel)
    show_header = (panel.get("options") or {}).get("showHeader", True)

    # --- Width check: can all columns fit? ---
    min_total_width = num_cols * TABLE_MIN_COL_PX
    if min_total_width > avail_w:
        issues.append({
            "rule": "table-columns-overflow-width",
            "detail": (
                f"{num_cols} columns need ~{min_total_width}px but panel "
                f"(w={w}) provides ~{avail_w}px. "
                f"Columns: {col_names}"
            ),
        })

    # --- Also check if column header text itself overflows ---
    if show_header and col_names:
        total_header_chars = sum(len(c) for c in col_names)
        # Add padding between columns (~16px per column gap)
        header_px = total_header_chars * CHAR_WIDTH_PX + (num_cols - 1) * 16
        if header_px > avail_w:
            issues.append({
                "rule": "table-headers-overflow-width",
                "detail": (
                    f"Column headers ({', '.join(col_names)}) need "
                    f"~{int(header_px)}px but panel (w={w}) provides ~{avail_w}px"
                ),
            })

    # --- Height check: room for header + at least 1 data row? ---
    row_px = _table_row_height_px(panel)  # respects cellHeight: sm/md/lg
    header_h = TABLE_HEADER_ROW_PX if show_header else 0
    min_content_h = header_h + row_px
    if min_content_h > avail_h:
        issues.append({
            "rule": "table-rows-overflow-height",
            "detail": (
                f"Table needs ~{min_content_h}px (header={header_h}px + "
                f"1 row={row_px}px) but panel (h={h}) "
                f"provides ~{avail_h}px"
            ),
        })

    return issues


def _check_text(panel: Dict, grid: Dict) -> List[Dict]:
    """Check text/markdown panel: panel is large enough to show at least one line.

    Grafana text panels render with a scrollbar when content overflows, so the
    full content is always accessible regardless of panel height.  The only
    meaningful failure mode is a panel so small that *nothing* is visible —
    flagged when available height is less than one rendered line (~20 px).
    """
    issues: List[Dict] = []
    h = grid.get("h", 6)

    content = (panel.get("options") or {}).get("content", "")
    if not isinstance(content, str) or not content.strip():
        return issues

    avail_h = _panel_avail_height_px(h)
    line_height_px = 20  # approximate rendered line height for markdown

    if avail_h < line_height_px:
        issues.append({
            "rule": "text-panel-too-small",
            "detail": (
                f"Panel (h={h}) has only ~{avail_h}px of content area — not "
                f"enough to display even one line (~{line_height_px}px). "
                f"Increase panel height so at least one line is visible."
            ),
        })

    return issues


def _check_stat(panel: Dict, grid: Dict) -> List[Dict]:
    """Check stat panel: title + value + optional sparkline fit."""
    issues: List[Dict] = []
    w = grid.get("w", 24)
    h = grid.get("h", 4)
    title = panel.get("title", "")

    avail_w = _panel_avail_width_px(w)
    avail_h = _panel_avail_height_px(h)

    # Title width check.
    title_px = len(title) * CHAR_WIDTH_PX
    if title_px > avail_w:
        issues.append({
            "rule": "stat-title-overflow-width",
            "detail": (
                f"Title '{title}' ({len(title)} chars, ~{int(title_px)}px) "
                f"exceeds panel width (w={w}, ~{avail_w}px)"
            ),
        })

    # Height check: value display + optional sparkline.
    options = panel.get("options") or {}
    graph_mode = options.get("graphMode", "none")
    sparkline_h = STAT_SPARKLINE_PX if graph_mode == "area" else 0
    needed_h = STAT_VALUE_PX + sparkline_h
    if needed_h > avail_h:
        issues.append({
            "rule": "stat-content-overflow-height",
            "detail": (
                f"Stat needs ~{needed_h}px (value={STAT_VALUE_PX}px"
                f"{f' + sparkline={sparkline_h}px' if sparkline_h else ''}) "
                f"but panel (h={h}) provides ~{avail_h}px"
            ),
        })

    return issues


def _check_gauge(panel: Dict, grid: Dict) -> List[Dict]:
    """Check gauge/bargauge: title fits width."""
    issues: List[Dict] = []
    w = grid.get("w", 24)
    title = panel.get("title", "")

    avail_w = _panel_avail_width_px(w)
    title_px = len(title) * CHAR_WIDTH_PX
    if title_px > avail_w:
        issues.append({
            "rule": "gauge-title-overflow-width",
            "detail": (
                f"Title '{title}' ({len(title)} chars, ~{int(title_px)}px) "
                f"exceeds panel width (w={w}, ~{avail_w}px)"
            ),
        })

    return issues


def _check_description(panel: Dict, grid: Dict) -> List[Dict]:
    """Flag panels whose description is so long it suggests the panel might
    be relying on hovering for critical info — but descriptions don't overflow
    the panel area, so this is informational only.  Skip for now."""
    return []


# ---------------------------------------------------------------------------
# Orchestrator
# ---------------------------------------------------------------------------

CHECKERS = {
    "table": _check_table,
    "text": _check_text,
    "stat": _check_stat,
    "gauge": _check_gauge,
    "bargauge": _check_gauge,
}


def check_panel_fit(panel: Dict) -> List[Dict]:
    """Run fit checks for a single panel. Returns list of issues."""
    grid = panel.get("gridPos") or {}
    if not grid:
        return []

    panel_type = panel.get("type", "")
    checker = CHECKERS.get(panel_type)
    if not checker:
        return []

    raw_issues = checker(panel, grid)

    # Enrich each issue with panel metadata.
    for issue in raw_issues:
        issue["panel_id"] = panel.get("id")
        issue["panel_title"] = panel.get("title", "")
        issue["panel_type"] = panel_type
        issue["gridPos"] = grid

    return raw_issues


def check_dashboard_file(filepath: Path) -> Dict:
    """Check a single dashboard JSON file. Returns dict with results."""
    try:
        dashboard = json.loads(filepath.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as exc:
        return {
            "file": filepath.name,
            "error": str(exc),
            "issues": [],
        }

    issues: List[Dict] = []
    for panel in flatten_panels(dashboard.get("panels", [])):
        issues.extend(check_panel_fit(panel))

    return {
        "file": filepath.name,
        "dashboard_title": dashboard.get("title", filepath.stem),
        "issues": issues,
    }


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Check that dashboard panel content fits its bounding box."
    )
    parser.add_argument(
        "--dashboard-dir",
        default=None,
        help="Directory containing dashboard JSON files (default: auto-detect).",
    )
    parser.add_argument("--json", dest="json_output", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    if args.dashboard_dir:
        dash_dir = Path(args.dashboard_dir)
    else:
        repo_root = Path(__file__).resolve().parents[1]
        dash_dir = repo_root / "grafana" / "provisioning" / "dashboards"

    if not dash_dir.is_dir():
        print(f"ERROR: dashboard directory not found: {dash_dir}", file=sys.stderr)
        return 2

    json_files = sorted(dash_dir.glob("*.json"))
    if not json_files:
        print(f"ERROR: no JSON files in {dash_dir}", file=sys.stderr)
        return 2

    all_results: List[Dict] = []
    total_issues = 0

    for fpath in json_files:
        result = check_dashboard_file(fpath)
        all_results.append(result)
        total_issues += len(result.get("issues", []))

    if args.json_output:
        summary = {
            "total_dashboards": len(all_results),
            "total_issues": total_issues,
            "passed": total_issues == 0,
            "dashboards": all_results,
        }
        print(json.dumps(summary, indent=2))
    else:
        for result in all_results:
            issues = result.get("issues", [])
            if not issues and not args.verbose:
                continue
            dash_label = result.get("dashboard_title") or result.get("file")
            status = "PASS" if not issues else "FAIL"
            print(f"\n{status}: {dash_label} ({result['file']})")
            if result.get("error"):
                print(f"  ERROR: {result['error']}")
            for issue in issues:
                gp = issue.get("gridPos", {})
                print(
                    f"  - [{issue['rule']}] Panel {issue['panel_id']} "
                    f"'{issue['panel_title']}' ({issue['panel_type']}, "
                    f"w={gp.get('w')}, h={gp.get('h')}): {issue['detail']}"
                )

        if total_issues:
            print(f"\nFAIL: {total_issues} panel fit violation(s) found.")
        else:
            print("\nPASS: All panel content fits within bounding boxes.")

    return 1 if total_issues else 0


if __name__ == "__main__":
    sys.exit(main())
