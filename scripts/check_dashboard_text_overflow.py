#!/usr/bin/env python3
"""
check_dashboard_text_overflow.py

Uses Playwright headless Chromium to render each Grafana dashboard and detect
text panels where markdown content overflows the visible panel area
(scrollHeight > clientHeight).

This is the live, ground-truth complement to the static
check_dashboard_panel_fit.py: instead of estimating heights from character
counts it renders the actual Grafana markdown and measures the real DOM.

Requirements
------------
- playwright Python package installed in the active venv
- Playwright Chromium browser installed:  ``playwright install chromium``
- Grafana running and reachable at GRAFANA_URL (default: http://grafana:3000)
- GRAFANA_TOKEN  *or*  GRAFANA_ADMIN_USER + GRAFANA_ADMIN_PASSWORD env vars

Usage
-----
    python scripts/check_dashboard_text_overflow.py           # human-readable
    python scripts/check_dashboard_text_overflow.py --json    # machine-readable
    python scripts/check_dashboard_text_overflow.py --verbose # show passing dashboards

Exit codes
----------
    0  all text panels fit within their bounding boxes
    1  one or more overflow violations found
    2  runtime error (Playwright unavailable, Grafana unreachable, auth failed)
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from typing import Any

# ---------------------------------------------------------------------------
# Configuration — all overridable via environment variables
# ---------------------------------------------------------------------------
GRAFANA_URL = os.environ.get("GRAFANA_URL", "http://grafana:3000").rstrip("/")
GRAFANA_TOKEN = os.environ.get("GRAFANA_TOKEN", "")
GRAFANA_USER = os.environ.get("GRAFANA_ADMIN_USER", "admin")
GRAFANA_PASSWORD = os.environ.get("GRAFANA_ADMIN_PASSWORD", "")
USE_BASIC_AUTH = bool(GRAFANA_USER and GRAFANA_PASSWORD)

# Viewport width matches the 1920px width assumed by the pixel-budget constants.
# Height is set very tall so ALL panels are within the initial viewport and
# Grafana's IntersectionObserver renders them all immediately — avoids the
# lazy-loading problem where panels below the fold are absent from the DOM.
VIEWPORT_WIDTH = 1920
VIEWPORT_HEIGHT = 8000

# Milliseconds to let panels finish rendering after navigation settles.
RENDER_SETTLE_MS = 3_000

# Ignore differences smaller than this to avoid 1-2 px rounding artifacts.
OVERFLOW_THRESHOLD_PX = 8

# Text panels can explicitly opt into scrollable overflow by declaring this
# marker in the panel description metadata.
OVERFLOW_POLICY_ALLOW_SCROLL_MARKER = "overflow-policy:allow-scroll"


# ---------------------------------------------------------------------------
# Grafana API helpers
# ---------------------------------------------------------------------------

def _api_headers() -> dict[str, str]:
    """Return auth headers for Grafana API calls.

    Prefer local admin credentials when present so a stale token in the
    environment does not break compose-based validation.
    """
    if GRAFANA_TOKEN and not USE_BASIC_AUTH:
        return {"Authorization": f"Bearer {GRAFANA_TOKEN}"}
    import base64
    creds = base64.b64encode(f"{GRAFANA_USER}:{GRAFANA_PASSWORD}".encode()).decode()
    return {"Authorization": f"Basic {creds}"}


def _api_get(page, path: str) -> Any:
    """Authenticated GET against the Grafana HTTP API."""
    resp = page.request.get(f"{GRAFANA_URL}{path}", headers=_api_headers())
    if not resp.ok:
        raise RuntimeError(f"Grafana API {path} → HTTP {resp.status}")
    return resp.json()


def _login(page) -> None:
    """Form-based login when no API token is configured."""
    page.goto(f"{GRAFANA_URL}/login", wait_until="networkidle")
    try:
        page.locator('input[name="user"]').wait_for(timeout=5_000)
    except Exception:
        return
    page.fill('input[name="user"]', GRAFANA_USER)
    page.fill('input[name="password"]', GRAFANA_PASSWORD)
    page.click('button[type="submit"]')
    page.wait_for_url(f"{GRAFANA_URL}/**", timeout=10_000)


# ---------------------------------------------------------------------------
# JavaScript injected into the browser to detect panel content overflow
# ---------------------------------------------------------------------------
# Grafana attaches the panel title test id to the text panel container
# section itself, so we can stay scoped to that subtree. Limiting the search
# to the text panel's converted markdown/code nodes avoids false positives
# from neighboring table grids rendered elsewhere in the dashboard layout.
_OVERFLOW_JS = f"""
(panelTitle) => {{
    // Find the text panel container by its data-testid attribute.
    const testId = 'data-testid Panel header ' + panelTitle;
    const panel = document.querySelector('[data-testid="' + testId + '"]');
    if (!panel) return {{ found: false }};

    const THRESHOLD = {OVERFLOW_THRESHOLD_PX};
    const MIN_CLIENT_H = 20;
    const candidates = panel.querySelectorAll(
        '[data-testid="TextPanel-converted-content"], .markdown-html, pre, code'
    );

    for (const el of candidates) {{
        if (el.clientHeight < MIN_CLIENT_H) continue;
        const diff = el.scrollHeight - el.clientHeight;
        if (diff > THRESHOLD) {{
            return {{
                found: true,
                overflow: true,
                scroll_height: el.scrollHeight,
                client_height: el.clientHeight,
                overflow_px: diff,
            }};
        }}
    }}
    return {{ found: true, overflow: false }};
}}
"""


# ---------------------------------------------------------------------------
# Per-dashboard check
# ---------------------------------------------------------------------------

def _flatten_panels(panels: list[dict]) -> list[dict]:
    """Recursively expand row children into a flat list."""
    result = []
    for p in panels:
        children = p.get("panels") or []
        if children:
            result.extend(_flatten_panels(children))
        elif p.get("type") != "row":
            result.append(p)
    return result


def _panel_allows_scroll(panel: dict[str, Any]) -> bool:
    """Return True when a panel explicitly declares scrollable overflow."""
    description = str(panel.get("description", "") or "")
    return OVERFLOW_POLICY_ALLOW_SCROLL_MARKER in description


def _build_issue(
    dashboard_title: str,
    dashboard_uid: str,
    panel: dict[str, Any],
    result: dict[str, Any],
) -> dict[str, Any]:
    gp = panel.get("gridPos", {})
    issue = {
        "dashboard": dashboard_title,
        "dashboard_uid": dashboard_uid,
        "panel_id": panel["id"],
        "panel_title": panel.get("title", ""),
        "gridPos": gp,
        "scroll_height_px": result["scroll_height"],
        "client_height_px": result["client_height"],
        "overflow_px": result["overflow_px"],
    }
    if _panel_allows_scroll(panel):
        issue["overflow_policy"] = OVERFLOW_POLICY_ALLOW_SCROLL_MARKER
    return issue


def check_dashboard(page, uid: str) -> tuple[str, list[dict], list[dict]]:
    """
    Render one dashboard and return ``(title, issues, approved_scrollable)``.

    ``issues`` contains gate-failing overflows; ``approved_scrollable`` contains
    overflows explicitly allowed by panel metadata.
    """
    detail = _api_get(page, f"/api/dashboards/uid/{uid}")
    dashboard = detail.get("dashboard", {})
    url_path = detail.get("meta", {}).get("url", f"/d/{uid}/dashboard")
    title = dashboard.get("title", uid)

    all_panels = _flatten_panels(dashboard.get("panels", []))
    text_panels = [
        p for p in all_panels
        if p.get("type") == "text" and "id" in p and "gridPos" in p
    ]
    if not text_panels:
        return title, [], []

    # Navigate with a broad time range so data panels also render cleanly.
    nav_url = f"{GRAFANA_URL}{url_path}?from=now-1y&to=now"
    page.goto(nav_url, wait_until="networkidle", timeout=30_000)
    page.wait_for_timeout(RENDER_SETTLE_MS)

    issues = []
    approved_scrollable = []
    for panel in text_panels:
        panel_title = panel.get("title", "")
        # JS lookup uses the panel title via data-testid; untitled panels are skipped.
        if not panel_title:
            continue
        result = page.evaluate(_OVERFLOW_JS, panel_title)
        if not result.get("found"):
            continue  # panel not in DOM (e.g. inside a collapsed row)
        if result.get("overflow"):
            issue = _build_issue(title, uid, panel, result)
            if _panel_allows_scroll(panel):
                approved_scrollable.append(issue)
            else:
                issues.append(issue)

    return title, issues, approved_scrollable


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(
        description="Playwright visual overflow check for Grafana text panels."
    )
    parser.add_argument("--json", dest="json_output", action="store_true")
    parser.add_argument("--verbose", action="store_true")
    args = parser.parse_args()

    def _err(msg: str) -> int:
        if args.json_output:
            print(json.dumps({"error": msg, "passed": False, "exit_code": 2}))
        else:
            print(f"ERROR: {msg}", file=sys.stderr)
        return 2

    # -- Dependency check ---------------------------------------------------
    try:
        from playwright.sync_api import sync_playwright
        from playwright.sync_api import TimeoutError as PlaywrightTimeout
    except ImportError:
        return _err(
            "playwright package not installed. "
            "Add playwright to dependencies and run: playwright install chromium"
        )

    # -- Credential check ---------------------------------------------------
    if not GRAFANA_TOKEN and not USE_BASIC_AUTH:
        return _err(
            "No Grafana credentials configured. "
            "Set GRAFANA_TOKEN or both GRAFANA_ADMIN_USER and GRAFANA_ADMIN_PASSWORD."
        )

    all_issues: list[dict] = []
    approved_scrollable_overflows: list[dict] = []
    warnings: list[str] = []
    total_dashboards = 0

    try:
        with sync_playwright() as pw:
            browser = pw.chromium.launch(headless=True)
            ctx = browser.new_context(
                viewport={"width": VIEWPORT_WIDTH, "height": VIEWPORT_HEIGHT},
                extra_http_headers=_api_headers(),
            )
            page = ctx.new_page()

            if USE_BASIC_AUTH:
                _login(page)

            search = _api_get(page, "/api/search?type=dash-db&limit=500")
            total_dashboards = len(search)

            for entry in search:
                uid = entry.get("uid", "")
                if not uid:
                    continue
                try:
                    title, issues, approved = check_dashboard(page, uid)
                    all_issues.extend(issues)
                    approved_scrollable_overflows.extend(approved)
                    if args.verbose and not issues and not approved:
                        print(f"  PASS: {title}")
                    elif args.verbose and not issues and approved:
                        print(
                            f"  PASS: {title} "
                            f"({len(approved)} approved scrollable overflow(s))"
                        )
                except PlaywrightTimeout:
                    warnings.append(f"{entry.get('title', uid)}: navigation timed out, skipped")
                except Exception as exc:
                    warnings.append(f"{entry.get('title', uid)}: {exc}")

            browser.close()

    except Exception as exc:
        return _err(f"Runtime error: {exc}")

    passed = len(all_issues) == 0
    summary = {
        "total_dashboards": total_dashboards,
        "total_violations": len(all_issues),
        "total_approved_scrollable_overflows": len(approved_scrollable_overflows),
        "passed": passed,
        "violations": all_issues,
        "approved_scrollable_overflows": approved_scrollable_overflows,
        "warnings": warnings,
    }

    if args.json_output:
        print(json.dumps(summary, indent=2))
    else:
        for w in warnings:
            print(f"  WARN: {w}", file=sys.stderr)
        for issue in approved_scrollable_overflows:
            gp = issue["gridPos"]
            print(
                f"  ALLOW: [{issue['dashboard']}] Panel {issue['panel_id']} "
                f"'{issue['panel_title']}' (w={gp.get('w')}, h={gp.get('h')}): "
                f"approved scrollable docs panel overflows by {issue['overflow_px']}px "
                f"(content={issue['scroll_height_px']}px, "
                f"visible={issue['client_height_px']}px)"
            )
        for issue in all_issues:
            gp = issue["gridPos"]
            print(
                f"  FAIL: [{issue['dashboard']}] Panel {issue['panel_id']} "
                f"'{issue['panel_title']}' (w={gp.get('w')}, h={gp.get('h')}): "
                f"overflows by {issue['overflow_px']}px "
                f"(content={issue['scroll_height_px']}px, "
                f"visible={issue['client_height_px']}px)"
            )
        if all_issues:
            print(
                f"\nFAIL: {len(all_issues)} text panel overflow(s) found "
                f"across {total_dashboards} dashboards."
            )
        else:
            print(
                f"\nPASS: All text panels fit within bounding boxes "
                f"({total_dashboards} dashboards checked)."
            )
            if approved_scrollable_overflows:
                print(
                    f"      {len(approved_scrollable_overflows)} approved "
                    f"scrollable docs panel(s) were exempted by policy."
                )

    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
