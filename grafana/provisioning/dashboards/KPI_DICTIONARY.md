# KPI Metric Dictionary and Formula Lineage

This document defines every headline KPI displayed across the Grafana dashboards.
It exists so any reader can trace a displayed number back to the exact SQL formula,
the dbt model that produces it, the grain at which it is computed, and the sign
convention applied.

Dashboard currency formatting uses USD units (`currencyUSD`) unless a panel is
explicitly configured otherwise. Percentages marked `percentunit` are stored as
0-1 ratios in the database; Grafana multiplies by 100 for display. Percentages
marked `percent` are stored pre-multiplied (0-100) in the database.

---

## 1. Net Cash Flow

| Attribute | Value |
|-----------|-------|
| **Formula** | `SUM(income_amount) - SUM(expense_amount)` per calendar month |
| **Grain** | Monthly (one row per YYYY-MM) |
| **Source model** | `reporting.rpt_monthly_budget_summary` |
| **Column** | `net_cash_flow` |
| **Sign convention** | Positive = surplus (more income than expenses). Negative = deficit. |
| **Internal transfers** | Excluded. `is_internal_transfer = TRUE` rows are filtered out before aggregation. |
| **Filter** | Completed calendar months only: `budget_year_month < current month` |
| **Notes** | Income = transactions where `is_income_transaction = TRUE` OR `transaction_amount > 0` (and not a transfer). Expenses = transactions where `transaction_amount < 0` (and not a transfer), stored as positive amounts for display. |

---

## 2. Savings Rate

| Attribute | Value |
|-----------|-------|
| **Formula** | `net_cash_flow / total_income` (ratio, 0-1) |
| **Grain** | Monthly |
| **Source model** | `reporting.rpt_monthly_budget_summary` |
| **Column** | `savings_rate_percent` (0-1 ratio); `savings_rate_pct` (0-100 for `percent` unit) |
| **Sign convention** | Positive = saving money. Negative = spending more than earned. |
| **Grafana unit** | `savings_rate_pct` uses Grafana `percent` unit (value already 0-100). |
| **Guard** | Returns 0 when `total_income = 0` to avoid division by zero. |
| **Notes** | This is the "total savings rate" (cash flow basis). The savings analysis dashboard also exposes a "traditional savings rate" that counts only explicit savings destinations (offset, cash savings, investments) divided by income. |

### Variant: Traditional Savings Rate

| Attribute | Value |
|-----------|-------|
| **Formula** | `(offset_savings + cash_savings + investment_contributions) / total_income` |
| **Source model** | `reporting.rpt_savings_analysis` |
| **Column** | `traditional_savings_rate_percent` (0-1 ratio) |
| **Notes** | Counts only money deliberately directed to savings vehicles. Excludes general surplus remaining after expenses. Lower than total savings rate when surplus stays in transaction accounts. |

---

## 3. Expense Ratio

| Attribute | Value |
|-----------|-------|
| **Formula** | `total_expenses / total_income` (ratio, 0-1) |
| **Grain** | Monthly |
| **Source model** | `reporting.rpt_monthly_budget_summary` |
| **Column** | `expense_ratio_percent` (0-1 ratio); `expense_ratio_pct` (0-100) |
| **Sign convention** | Values above 1.0 (or 100%) mean spending exceeded income. |
| **Grafana unit** | `expense_ratio_pct` uses Grafana `percent` unit. |
| **Notes** | Threshold 115% triggers red colour in Grafana threshold rules. Target is below 100%. |

---

## 4. Emergency Fund Coverage

| Attribute | Value |
|-----------|-------|
| **Formula** | `liquid_assets / avg_monthly_essential_expenses` (months) |
| **Grain** | Point-in-time (latest completed month) |
| **Source model** | `reporting.rpt_emergency_fund_coverage` |
| **Column** | `months_essential_expenses_covered` |
| **Sign convention** | Higher is better. Target is 6 months. |
| **Essential expenses definition** | `mortgage_expenses + household_expenses + food_expenses + family_expenses` (last 6 completed months average from `rpt_monthly_budget_summary`) |
| **Liquid assets source** | `rpt_household_net_worth.liquid_assets` = sum of account balances where `dim_accounts.is_liquid_asset = TRUE` |
| **Status tiers** | Excellent >= 6 months; Good >= 3; Low >= 1; Critical < 1 |
| **Notes** | A second metric `months_total_expenses_covered` uses all expenses (not just essentials). The gauge on the Executive dashboard shows essential-expense coverage as the more conservative measure. |

---

## 5. Net Worth

| Attribute | Value |
|-----------|-------|
| **Formula** | `SUM(ABS(balance) WHERE NOT is_liability) - SUM(ABS(balance) WHERE is_liability)` |
| **Grain** | Monthly (end-of-month balance per account) |
| **Source model** | `reporting.rpt_household_net_worth` |
| **Column** | `net_worth` |
| **Sign convention** | Positive = assets exceed liabilities. |
| **Asset sources** | Bank account balances from `fct_transactions.account_balance` (MAX per month), plus property asset values from `int_property_assets_monthly` (seeded via `property_assets.csv`). |
| **Notes** | The `is_liability` flag comes from `dim_accounts` which reads from the `known_values.csv` seed. Balances are taken as the maximum transaction-date balance within each month (acts as end-of-month proxy). |

### Sub-metrics

| KPI | Formula | Column |
|-----|---------|--------|
| Total Assets | `SUM(ABS(balance)) WHERE NOT is_liability` | `total_assets` |
| Total Liabilities | `SUM(ABS(balance)) WHERE is_liability` | `total_liabilities` |
| Liquid Assets | `SUM(ABS(balance)) WHERE is_liquid_asset = TRUE` | `liquid_assets` |
| Mortgage Debt | `SUM(ABS(balance)) WHERE is_mortgage = TRUE` | `mortgage_debt` |
| Debt-to-Asset Ratio | `total_liabilities / total_assets` (0-1 ratio) | `debt_to_asset_ratio` |

---

## 6. Financial Health Scores (0-100)

All scores are dimensionless integers on a 0-100 scale. Higher is better.

### Overall Financial Health Score

| Attribute | Value |
|-----------|-------|
| **Formula** | Weighted average of seven dimension scores |
| **Weights** | Savings 20%, Net Worth 20%, Cash Flow 15%, Emergency Fund 15%, Income Stability 10%, Debt Management 10%, Spending Control 10% |
| **Source model** | `reporting.rpt_financial_health_scorecard` |
| **Column** | `overall_financial_health_score` |
| **Rating bands** | >= 85 Excellent; >= 70 Very Good; >= 60 Good; >= 50 Fair; >= 40 Needs Improvement; < 40 Poor |

### Dimension Score Formulas

| Score | Formula Summary | Column |
|-------|----------------|--------|
| **Savings Score** | Based on `total_savings_rate_percent` thresholds + improvement bonus + consistency bonus | `savings_health_score` in `rpt_savings_analysis` |
| **Net Worth Score** | Base 50 + positive NW (+20) + D/A ratio < 0.5 (+15) + MoM growth (+10) + liquidity ratio > 0.2 (+5) | `net_worth_health_score` in `rpt_household_net_worth` |
| **Cash Flow Score** | Base 50 + positive cash flow (+30) + margin > 10% (+20) + outflow ratio < 80% (+10/-10) | `cash_flow_efficiency_score` in `rpt_cash_flow_analysis` |
| **Emergency Fund Score** | Tiered: >= 12 months = 100; >= 6 = 85; >= 3 = 70; >= 1 = 50; < 1 = 25 | Calculated inline in `rpt_financial_health_scorecard` |
| **Income Stability Score** | Based on coefficient of variation (stddev/mean) of last 6 months of income | `income_stability_score` (inline) |
| **Debt Management Score** | Based on `total_liabilities / monthly_income` ratio thresholds | `debt_management_score` (inline) |
| **Spending Control Score** | Current month expenses vs 3-month average: decrease = 100; < 5% increase = 85; etc. | `spending_control_score` (inline) |

---

## 7. Family Essentials

| Attribute | Value |
|-----------|-------|
| **Formula** | `SUM(ABS(transaction_amount)) WHERE level_1_category IN ('Food & Drink', 'Family & Kids', 'Health & Beauty', 'Household & Services') AND transaction_amount < 0 AND NOT is_internal_transfer` |
| **Grain** | Latest completed month only (single-row output) |
| **Source model** | `reporting.rpt_family_essentials` |
| **Column** | `total_family_essentials` |
| **Sign convention** | Always positive (expenses are sign-flipped to positive for display). |
| **Notes** | Returns the most recent fully-closed calendar month. Excludes the current in-progress month. Splits are available per category: `groceries_spending`, `family_kids_spending`, `health_spending`, `household_spending`. |

---

## 8. Cash Flow Margin

| Attribute | Value |
|-----------|-------|
| **Formula** | `net_cash_flow / total_inflows` (0-1 ratio) |
| **Grain** | Monthly |
| **Source model** | `reporting.rpt_cash_flow_analysis` |
| **Column** | `cash_flow_margin_percent` |
| **Sign convention** | Positive = surplus; negative = deficit. |
| **Notes** | `total_inflows` in `rpt_cash_flow_analysis` includes all non-transfer inflows (both income-flagged and positive non-income amounts). This differs slightly from `total_income` in `rpt_monthly_budget_summary`. |

---

## 9. Month-over-Month Rate Changes

| KPI | Formula | Column | Source model |
|-----|---------|--------|-------------|
| Savings Rate MoM | `(current_savings_rate - prev_savings_rate) / ABS(prev_savings_rate)` | `delta_ratio` (panel query output) | `rpt_monthly_budget_summary.savings_rate_percent` (current/previous month) |
| Expense Ratio MoM | `(current_expense_ratio - prev_expense_ratio) / ABS(prev_expense_ratio)` | `delta_ratio` (panel query output) | `rpt_cash_flow_analysis.outflow_to_inflow_ratio` (current/previous month) |

---

## 10. Forecasted Next Month Net Flow

| Attribute | Value |
|-----------|-------|
| **Formula** | `rolling_3m_avg_net_flow * 1.05` (if trend = Improving), `* 0.95` (if Declining), else `* 1.0` |
| **Source model** | `reporting.rpt_cash_flow_analysis` |
| **Column** | `forecasted_next_month_net_flow` |
| **Notes** | Simple trend extrapolation only. Not a statistical model. Shown on the Executive Summary text panel as a directional indicator. |

---

## 11. YTD Metrics

| KPI | Formula | Source |
|-----|---------|--------|
| YTD Income | `SUM(total_income) PARTITION BY budget_year ORDER BY budget_month` | `rpt_monthly_budget_summary.ytd_income` |
| YTD Expenses | `SUM(total_expenses) PARTITION BY budget_year ORDER BY budget_month` | `rpt_monthly_budget_summary.ytd_expenses` |
| YTD Net Cash Flow | `SUM(net_cash_flow) PARTITION BY budget_year ORDER BY budget_month` | `rpt_monthly_budget_summary.ytd_net_cash_flow` |
| YTD Savings Rate | `ytd_net_cash_flow / ytd_income` (0-1 ratio) | `rpt_monthly_budget_summary.savings_rate_ytd_pct` (stored * 100) |

---

## Data Lineage Summary

```
QIF files (raw)
  └── landing schema (raw ingestion via Dagster)
        └── staging schema (dbt staging models)
              └── fct_transactions (transformation schema)
                    ├── dim_accounts (from known_values.csv seed)
                    ├── dim_categories (from banking_categories.csv seed)
                    │
                    ├── rpt_monthly_budget_summary   → Net Cash Flow, Savings Rate, Expense Ratio
                    ├── rpt_savings_analysis         → Traditional Savings Rate, Savings Health Score
                    ├── rpt_household_net_worth      → Net Worth, Liquid Assets, Debt-to-Asset Ratio
                    ├── rpt_emergency_fund_coverage  → Emergency Fund Coverage (months)
                    ├── rpt_cash_flow_analysis       → Cash Flow Margin, Efficiency Score, Forecast
                    ├── rpt_financial_health_scorecard → Composite Health Scores
                    ├── rpt_family_essentials        → Family Essentials Spending
                    ├── rpt_mom_cash_flow_summary    → MoM net-flow/inflow/outflow delta table
                    └── rpt_monthly_budget_summary + rpt_cash_flow_analysis → Executive MoM Rate Changes (Savings/Expense)
```

---

## Percentage Formatting Reference

| Grafana unit | DB value format | Example DB value | Example display |
|-------------|----------------|-----------------|-----------------|
| `percent` | Pre-multiplied (0-100) | `savings_rate_pct = -15.4` | -15.4% |
| `percentunit` | Ratio (0-1) | `savings_rate_percent = -0.154` | -15.4% |
| None (numeric) | Raw number | `net_cash_flow = -1977` | -1977 |

The field naming convention is:
- `field_name` = 0-1 ratio (used with `percentunit`)
- `field_name_pct` = 0-100 (used with `percent`)

---

*Last updated: 2026-02-21. Maintained alongside dbt model changes.*
