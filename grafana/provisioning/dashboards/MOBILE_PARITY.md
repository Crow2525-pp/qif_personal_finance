# Mobile-Desktop KPI Parity Report

**Task:** 55 — Desktop-Mobile KPI Parity Contract
**Date:** 2026-02-21
**Branch:** `feat/task-55-desktop-mobile-kpi-parity`

---

## Summary

All six mobile dashboards were audited against their desktop counterparts and corrected to use
consistent units, thresholds, and formatting conventions. An automated parity check was added to
`scripts/check_grafana_dashboards.py` that flags any mobile dashboard panel still using a
forbidden currency unit.

---

## Parity Issues Found and Fixed

### 1. Unit Mismatches: `currencyUSD` on All Mobile Dashboards

**Problem:** Every monetary panel in all six mobile dashboards used `unit: "currencyUSD"`. The
project convention (CLAUDE.md) requires `unit: "short"` for monetary values — no currency symbols.

**Affected panels (37 total across all 6 dashboards):**

| Dashboard | Panel | Title |
|-----------|-------|-------|
| 01-executive-overview-mobile | 2 | Key Metrics |
| 01-executive-overview-mobile | 3 | 12-Month Cash Flow Trend |
| 01-executive-overview-mobile | 4 | Account Balances |
| 01-executive-overview-mobile | 5 | Top Spending |
| 01-executive-overview-mobile | 9 | Top 5 Uncategorized Transactions |
| 02-cash-flow-budget-mobile | 1 | Net Cash Flow |
| 02-cash-flow-budget-mobile | 2 | Total Income |
| 02-cash-flow-budget-mobile | 3 | Total Expenses |
| 02-cash-flow-budget-mobile | 4 | 24-Month Income vs Expenses Trend |
| 02-cash-flow-budget-mobile | 7 | 24-Month Net Cash Flow History |
| 03-spending-categories-mobile | 1 | Top 10 Categories with MoM Change |
| 03-spending-categories-mobile | 2 | Current Month Spending Breakdown |
| 03-spending-categories-mobile | 3 | 12-Month Total Expenses Trend |
| 03-spending-categories-mobile | 4 | Top 5 Categories - 12-Month Trends |
| 03-spending-categories-mobile | 5 | Large Transactions (>$500) |
| 03-spending-categories-mobile | 7 | 12-Month Average Grocery Spending |
| 03-spending-categories-mobile | 8 | Current Month Market Share |
| 03-spending-categories-mobile | 9 | 18-Month Grocery Spending Trends |
| 03-spending-categories-mobile | 10 | Large Transactions (>$500) - External |
| 04-assets-networth-mobile | 1 | Net Worth |
| 04-assets-networth-mobile | 2 | Total Assets |
| 04-assets-networth-mobile | 3 | Total Liabilities |
| 04-assets-networth-mobile | 4 | 24-Month Net Worth Trend |
| 04-assets-networth-mobile | 5 | Account Balances with MoM Changes |
| 04-assets-networth-mobile | 6 | Asset Allocation by Account Type |
| 05-savings-performance-mobile | 5 | Year-to-Date Savings |
| 05-savings-performance-mobile | 6 | Projected Annual Savings |
| 05-savings-performance-mobile | 7 | Current Month Savings Breakdown |
| 05-savings-performance-mobile | 9 | Performance Metrics MoM Analysis |
| 06-projections-analysis-mobile | 1 | 12-Month Financial Projections |
| 06-projections-analysis-mobile | 2 | 12-Month Average Projections |
| 06-projections-analysis-mobile | 3 | 12-Month Part-time Opportunity Cost |
| 06-projections-analysis-mobile | 5 | Year-to-Date Performance vs Previous Year |
| 06-projections-analysis-mobile | 6 | 4-Year Annual Financial Comparison |

**Fix:** Changed `unit: "currencyUSD"` to `unit: "short"` in `fieldConfig.defaults` for all
affected panels. No override-level `currencyUSD` entries were found.

---

### 2. Threshold Mismatch: Savings Rate (Mobile 02 Panel 5)

**Problem:** Mobile savings rate gauge used different threshold breakpoints from desktop.

| | Yellow threshold | Green threshold | min | max |
|--|--|--|--|--|
| Mobile (before) | 0.10 (10%) | 0.20 (20%) | none | none |
| Desktop (savings-analysis Panel 2) | 0.05 (5%) | 0.15 (15%) | 0 | 0.5 |

**Fix:** Updated mobile Panel 5 thresholds to match desktop: `yellow=0.05`, `green=0.15`,
`min=0`, `max=0.5`.

---

### 3. Threshold and Unit Mismatch: Savings Health Score (Mobile 05 Panel 1)

**Problem:** Mobile savings health score gauge used `unit: "percent"` (expects 0-100 values)
with thresholds of 60/80, while desktop uses `unit: "short"` with thresholds of 50/75.

| | Unit | Yellow | Green | min | max |
|--|--|--|--|--|--|
| Mobile (before) | percent | 60 | 80 | none | none |
| Desktop (savings-analysis Panel 1) | short | 50 | 75 | 0 | 100 |

**Fix:** Updated mobile Panel 1 to `unit: "short"`, thresholds `yellow=50`, `green=75`,
`min=0`, `max=100`.

---

## SQL Source Analysis

Mobile dashboards use purpose-appropriate reporting tables — no mismatches requiring fixes:

- `02-cash-flow-budget-mobile`: All panels query `reporting.rpt_monthly_budget_summary` (same as desktop cash-flow panel).
- `04-assets-networth-mobile`: Queries `reporting.rpt_household_net_worth` (matches desktop).
- `05-savings-performance-mobile`: Queries `reporting.rpt_savings_analysis` (matches desktop).
- `06-projections-analysis-mobile`: Queries `reporting.fct_financial_projections` (matches desktop).
- `01-executive-overview-mobile` Panel 1: Queries `reporting.rpt_executive_dashboard` — differs from desktop Panel 6 which uses `rpt_monthly_budget_summary`, but this is intentional (executive dashboard provides pre-computed health scores).

---

## Automated Parity Check

A new `lint_mobile_parity()` function was added to `scripts/check_grafana_dashboards.py`.

**How it works:**
- Identifies mobile dashboards by title containing "mobile" or the mobile phone emoji.
- Scans all panels in `fieldConfig.defaults.unit` and `fieldConfig.overrides[*].properties[unit]`.
- Flags any panel using `currencyUSD`, `currencyAUD`, `currencyGBP`, or `currencyEUR` as a WARNING.
- Parity warnings count toward the total lint/warning count and cause a non-zero exit.

**New CLI flag:** `--no-parity` skips parity checks (similar to `--no-lint`).

**Running parity-only checks:**
```bash
GRAFANA_URL=http://localhost:3001 \
GRAFANA_USER=admin GRAFANA_PASSWORD=testadmin \
python scripts/check_grafana_dashboards.py --no-lint --dashboard "mobile"
```

After fixes were applied, all 6 mobile dashboards report `0 parity warnings`.

---

## Changes Committed

**Files modified:**
- `grafana/provisioning/dashboards/01-executive-overview-mobile.json` — 5 panels: unit fix
- `grafana/provisioning/dashboards/02-cash-flow-budget-mobile.json` — 5 panels: unit fix, savings rate threshold alignment
- `grafana/provisioning/dashboards/03-spending-categories-mobile.json` — 9 panels: unit fix
- `grafana/provisioning/dashboards/04-assets-networth-mobile.json` — 6 panels: unit fix
- `grafana/provisioning/dashboards/05-savings-performance-mobile.json` — 5 panels: unit + threshold fixes (savings health score)
- `grafana/provisioning/dashboards/06-projections-analysis-mobile.json` — 5 panels: unit fix
- `scripts/check_grafana_dashboards.py` — Added `lint_mobile_parity()`, `--no-parity` flag, parity warning output

**All 6 dashboards pushed to Grafana API (localhost:3001) and confirmed accepted (HTTP 200).**
