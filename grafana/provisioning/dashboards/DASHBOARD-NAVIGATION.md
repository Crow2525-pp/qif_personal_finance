# Dashboard Navigation Guide

## Overview

This document outlines the dashboard structure, navigation paths, and which dashboards are optimized for mobile versus full detail desktop viewing.

## Dashboard Hierarchy

### Executive Hub
**Executive Financial Overview** (`executive-dashboard.json`)
- **Type**: Full Detail / Desktop
- **Purpose**: Central dashboard for comprehensive financial overview with KPIs and trend analysis
- **Cross-Links**: Primary navigation hub with links to all major analysis dashboards
- **Content**: Summary metrics, financial health scoring, forecasts, and key ratios
- **Best For**: Monthly reviews, executive summaries, drill-down starting point

### Core Analysis Dashboards (Full Detail - Desktop Optimized)

#### Cash Flow Analysis
- **File**: `cash-flow-analysis-dashboard.json`
- **Purpose**: Detailed cash flow trends, net flow trends, and forecasting
- **Content**: Monthly cash flow breakdown, income vs expense trends, cash flow state machine visualization
- **Linked From**: Executive Dashboard

#### Monthly Budget Summary
- **File**: `monthly-budget-summary-dashboard.json`
- **Purpose**: Budget vs actual comparison for monthly performance tracking
- **Content**: Budget categories, actual spending, variances, and ratio analysis
- **Linked From**: Executive Dashboard

#### Category Spending Analysis
- **File**: `category-spending-dashboard.json`
- **Purpose**: Detailed breakdown of spending by transaction category
- **Content**: Spending trends by category, merchant insights, category comparisons
- **Linked From**: Executive Dashboard

#### Household Net Worth
- **File**: `household-net-worth-dashboard.json`
- **Purpose**: Net worth composition, asset allocation, and wealth trends
- **Content**: Asset breakdown, liability tracking, net worth progression, milestone tracking
- **Linked From**: Executive Dashboard

#### Savings Performance
- **File**: `savings-analysis-dashboard.json`
- **Purpose**: Savings rate analysis, goal tracking, and performance trends
- **Content**: Monthly savings rate, goal progress, savings effectiveness, income allocation
- **Linked From**: Executive Dashboard

### Mobile Dashboards (Mobile Optimized - Compact/Single Screen)

The following dashboards are specifically designed for mobile viewing with compact layouts:

| Dashboard | File | Purpose |
|-----------|------|---------|
| Executive Overview (Mobile) | `01-executive-overview-mobile.json` | Key KPIs summary for quick mobile review |
| Cash Flow & Budget (Mobile) | `02-cash-flow-budget-mobile.json` | Combined cash flow and budget trends for mobile |
| Spending Categories (Mobile) | `03-spending-categories-mobile.json` | Mobile-friendly category spending breakdown |
| Assets & Net Worth (Mobile) | `04-assets-networth-mobile.json` | Net worth summary optimized for mobile |
| Savings Performance (Mobile) | `05-savings-performance-mobile.json` | Savings metrics in mobile format |
| Projections Analysis (Mobile) | `06-projections-analysis-mobile.json` | Financial projections for mobile viewing |

**Mobile Dashboard Features**:
- Optimized for vertical scrolling
- Reduced panel density
- Larger fonts for readability on small screens
- Simplified metrics focused on key indicators
- Designed for daily check-ins and quick reviews

### Specialty/Deep-Dive Dashboards

#### Account Performance
- **File**: `account-performance-dashboard.json`
- **Type**: Full Detail
- **Purpose**: Detailed analysis of individual bank account performance
- **Content**: Account balance trends, transaction volume, account-specific metrics

#### Outflows & Reconciliation
- **File**: `outflows-reconciliation-dashboard.json` / `outflows-insights-dashboard.json`
- **Type**: Full Detail
- **Purpose**: Track outflows for reconciliation and identify patterns

#### Transaction Analysis
- **File**: `transaction-analysis-dashboard.json`
- **Type**: Full Detail
- **Purpose**: Detailed transaction-level analysis and patterns

#### Merchant Spending (Amazon/Grocery)
- **Files**: `amazon-spending-dashboard.json`, `grocery-spending-dashboard.json`
- **Type**: Full Detail
- **Purpose**: Specific merchant or category deep-dives

#### Expense Performance
- **File**: `expense-performance-dashboard.json`
- **Type**: Full Detail
- **Purpose**: Track expense efficiency and cost management

#### Financial Projections
- **File**: `financial-projections-dashboard.json`
- **Type**: Full Detail
- **Purpose**: Long-term financial forecasting and scenario analysis

#### Mortgage & Net Worth Details
- **Files**: `mortgage-payoff-dashboard.json`, `net-worth-liquidity.json`, `net-worth-mortgage.json`
- **Type**: Full Detail
- **Purpose**: Mortgage tracking and net worth component analysis

#### Comparative Analysis
- **Files**: `four-year-financial-comparison-dashboard.json`, `year-over-year-comparison-dashboard.json`
- **Type**: Full Detail
- **Purpose**: Multi-year trend comparison and historical analysis

## Navigation Recommendations

### Daily/Weekly Routine
1. Start with **Mobile Dashboard** (Executive Overview Mobile) for quick status check
2. If deeper analysis needed, access **Executive Financial Overview** for detailed view

### Monthly Review
1. Open **Executive Financial Overview** for comprehensive overview
2. Use cross-links to drill into specific areas:
   - Budget variance → Monthly Budget Summary
   - Spending patterns → Category Spending Analysis
   - Cash position → Cash Flow Analysis
   - Wealth changes → Household Net Worth
   - Savings progress → Savings Performance

### Detailed Analysis
1. Use specialty dashboards for merchant or category deep-dives
2. Access comparative dashboards for year-over-year or multi-year analysis
3. Review reconciliation dashboards for transaction validation

## Panel Consolidation

### Consolidated Data Sources
The following concepts appear across multiple dashboards but pull from authoritative models:

- **Cash Flow Metrics**: `rpt_cash_flow_analysis` table is the authoritative source
  - Executive Dashboard: Summary view
  - Cash Flow Analysis: Detailed breakdown
  - Mobile Dashboard: Compact summary

- **Budget Performance**: `rpt_monthly_budget_summary` table is authoritative
  - Executive Dashboard: High-level variance
  - Monthly Budget Summary: Detailed budget-to-actual
  - Category Spending: Category-level performance

- **Savings Rate**: Calculated from `rpt_monthly_budget_summary`
  - Executive Dashboard: Key ratio view
  - Savings Performance: Detailed savings analysis
  - Mobile Dashboard: Quick metric

- **Net Worth**: `rpt_household_net_worth` and related tables
  - Executive Dashboard: Total net worth and trend
  - Household Net Worth: Full composition
  - Mobile Dashboard: Summary view

### Repeated Visual Patterns
The following visualization patterns are intentionally repeated for consistency:
- Cash flow trend (line chart) appears in multiple dashboards
- Savings rate gauge appears in multiple dashboards
- Budget variance bar chart appears in multiple dashboards

These are designed to be self-contained views for specific drill-down paths, ensuring users don't need to navigate between multiple dashboards for related metrics.

## Dashboard Maintenance Notes

- All mobile dashboards should be reviewed monthly for consistency with desktop counterparts
- Cross-links in the Executive Dashboard should be updated when dashboard UIDs change
- Repeated panels should pull from the same authoritative data models to prevent metric inconsistencies
- Dashboard ordering (01-, 02-, etc. for mobile) maintains logical grouping for navigation menus

