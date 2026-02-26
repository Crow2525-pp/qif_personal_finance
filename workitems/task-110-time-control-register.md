# Task 110 Time Control Register

| dashboard_uid | archetype | exception_type | status | quick_ranges_label_set | default_time.from | default_time.to | timepicker_hidden | notes |
|---|---|---|---|---|---|---|---|---|
| financial-review-command-center | atemporal_no_time_component | no_time_component | exception-tagged | none | now-1y | now | true | navigation shell, no time filtering |
| exec-mobile-overview | historical_windowed | — | compliant | historical | now-1M/M | now/M | false | mobile executive overview |
| cashflow-budget-mobile | historical_windowed | — | compliant | historical | now-1M/M | now/M | false | mobile cash flow |
| spending-categories-mobile | historical_windowed | — | compliant | historical | now-1M/M | now/M | false | mobile spending categories |
| assets-networth-mobile | historical_windowed | — | compliant | historical | now-1M/M | now/M | false | mobile assets/net worth |
| savings-performance-mobile | historical_windowed | — | compliant | historical | now-1M/M | now/M | false | mobile savings performance |
| projections-analysis-mobile | forward_looking | forward_looking | exception-tagged | forward_looking | now | now+5y | false | mobile projections |
| account_performance_dashboard | historical_windowed | — | compliant | historical | now-1M/M | now/M | false | account balances and trends |
| amazon-spending | historical_windowed | — | compliant | historical | now-1M/M | now/M | false | Amazon spending analysis |
| cash_flow_analysis | historical_windowed | — | compliant | historical | now-1M/M | now/M | false | income/expense trends |
| category-spending-v2 | historical_windowed | — | compliant | historical | now-1M/M | now/M | false | spending by category |
| executive_dashboard | historical_windowed | — | compliant | historical | now-1M/M | now/M | false | main KPI overview |
| expense_performance | historical_windowed | — | compliant | historical | now-1M/M | now/M | false | expense analysis |
| financial_projections | forward_looking | forward_looking | exception-tagged | forward_looking | now | now+5y | false | financial projections and scenarios |
| four_year_financial_comparison | historical_fixed_period | time_specific | exception-tagged | fixed_period | now-5y | now | false | multi-year comparison |
| grocery_spending_analysis | historical_windowed | — | compliant | historical | now-1M/M | now/M | false | grocery spending trends |
| household_net_worth | historical_windowed | — | compliant | historical | now-1M/M | now/M | false | household assets/liabilities |
| monthly_budget_summary | historical_windowed | — | compliant | historical | now-1M/M | now/M | false | monthly budget vs actual |
| mortgage-payoff | hybrid_past_future | hybrid_future_component | exception-tagged | hybrid | now-10y | now+5y | false | mortgage history + projections |
| outflows_insights | historical_windowed | — | compliant | historical | now-1M/M | now/M | false | outflow analysis |
| outflows_reconciliation | historical_windowed | — | compliant | historical | now-1M/M | now/M | false | reconciliation quality |
| savings_analysis | historical_windowed | — | compliant | historical | now-1M/M | now/M | false | savings rates and goals |
| transaction_analysis_dashboard | historical_windowed | — | compliant | historical | now-1M/M | now/M | false | transaction-level analysis |
| year_over_year_comparison | historical_fixed_period | time_specific | exception-tagged | fixed_period | now-5y | now | false | YoY comparison |
