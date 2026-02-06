# Dashboard Fixes Plan

[
  {
    "id": 28,
    "category": "dashboard-fix",
    "title": "Cash Flow Drivers panel renders without visible data",
    "description": "Cash Flow Drivers (Month-over-Month) shows only the title with no visible chart or table content. Ensure the visualization is rendered (or show an explicit 'No data' state) so users know whether it is blank by design or broken.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Cash Flow Drivers panel",
    "effort": "small",
    "status": "pending",
    "notes": "Observed on 2026-02-06 at 2560x1307: panel text content only contains the title."
  },
  {
    "id": 29,
    "category": "dashboard-fix",
    "title": "How-to-Read text references a Month selector that is not present",
    "description": "The How to Read section says the Month selector swaps the anchored month, but no Month selector control is visible on the dashboard. Either add the selector or update the instructions to match the actual UI.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; How to Read panel; dashboard variables",
    "effort": "tiny",
    "status": "pending",
    "notes": "Verified on 2026-02-06: no visible Month variable control."
  },
  {
    "id": 30,
    "category": "dashboard-fix",
    "title": "Monthly Savings duplicates Net Cash Flow value",
    "description": "Monthly Financial Snapshot shows 'Net Cash Flow' and 'Monthly Savings' with the same value, which is confusing without a definition. Either differentiate the measures or add a note explaining why they are identical.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Monthly Financial Snapshot panel",
    "effort": "tiny",
    "status": "pending",
    "notes": "Observed on 2026-02-06: both values display -$1.98K."
  },
  {
    "id": 31,
    "category": "dashboard-fix",
    "title": "Executive Summary formatting is hard to scan",
    "description": "The Executive Summary is a single long pipe-delimited sentence. Replace with a short list or key-value layout so critical metrics are scannable, especially on large screens.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Executive Summary panel",
    "effort": "tiny",
    "status": "pending",
    "notes": "Usability review on 2026-02-06: users must parse long inline text."
  },
  {
    "id": 32,
    "category": "dashboard-fix",
    "title": "Data Quality Callouts headers are inconsistent with other tables",
    "description": "Data Quality Callouts uses lowercase headers ('metric', 'value', 'detail') while other tables use title case. Standardize header casing for visual consistency.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Data Quality Callouts panel",
    "effort": "tiny",
    "status": "pending",
    "notes": "Observed on 2026-02-06."
  },
  {
    "id": 33,
    "category": "dashboard-fix",
    "title": "Data Quality Callouts percentages lack definition",
    "description": "Percentages in Data Quality Callouts (e.g., 1%, 3%, 87.1%) do not define the denominator (by count, by spend, or by accounts). Add a brief note or tooltip clarifying what each percentage represents.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Data Quality Callouts panel",
    "effort": "tiny",
    "status": "pending",
    "notes": "Usability review on 2026-02-06: percent meaning is ambiguous."
  },
  {
    "id": 34,
    "category": "dashboard-fix",
    "title": "Top Uncategorized Merchants lacks time window context",
    "description": "Top Uncategorized Merchants doesn't state the period the list covers (current month vs last 30 days). Add a subtitle or description that clarifies the date window and whether it follows the global time picker or a fixed month.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Top Uncategorized Merchants panel",
    "effort": "tiny",
    "status": "pending",
    "notes": "Usability review on 2026-02-06: time basis not explicit."
  },
  {
    "id": 35,
    "category": "dashboard-fix",
    "title": "Top Uncategorized Merchants 'Contribution %' ambiguous",
    "description": "The Contribution % column does not clarify whether it is a share of total uncategorized spend, all spend, or a category subset. Add a column description or rename to specify the denominator.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Top Uncategorized Merchants panel",
    "effort": "tiny",
    "status": "pending",
    "notes": "Usability review on 2026-02-06: percent meaning unclear."
  },
  {
    "id": 36,
    "category": "dashboard-fix",
    "title": "AI Financial Insights uses generic 'None flagged' without criteria",
    "description": "AI Financial Insights shows 'None flagged' for Accounts Needing Attention but doesn't define the criteria or threshold for being flagged. Add a description that explains what triggers a flag and what 'None flagged' means.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; AI Financial Insights panel",
    "effort": "tiny",
    "status": "pending",
    "notes": "Usability review on 2026-02-06."
  },
  {
    "id": 37,
    "category": "dashboard-fix",
    "title": "AI Financial Insights recommendation lacks actionable link or owner",
    "description": "The priority recommendation is phrased as advice but doesn't link to a supporting drill-down or indicate an owner. Add a link to the relevant analysis or include a 'why' note so it is actionable.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; AI Financial Insights panel",
    "effort": "small",
    "status": "pending",
    "notes": "Usability review on 2026-02-06: recommendation feels orphaned."
  },
  {
    "id": 38,
    "category": "dashboard-fix",
    "title": "Status Highlights table headers are lowercase and vague",
    "description": "Status Highlights uses lowercase headers ('metric', 'status', 'detail') and generic wording. Standardize header casing and consider renaming to clearer labels (e.g., 'Signal', 'Status', 'Explanation').",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Status Highlights panel",
    "effort": "tiny",
    "status": "pending",
    "notes": "Usability review on 2026-02-06."
  },
  {
    "id": 39,
    "category": "dashboard-fix",
    "title": "Asset & Liability Snapshot lacks trend or comparison",
    "description": "Asset & Liability Snapshot is a set of static totals without a comparison to previous month/year. Add deltas or sparklines so users can interpret movement, not just current size.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Asset & Liability Snapshot panel",
    "effort": "small",
    "status": "pending",
    "notes": "Usability review on 2026-02-06: static totals are less informative."
  },
  {
    "id": 40,
    "category": "dashboard-fix",
    "title": "Monthly Financial Snapshot lacks variance context",
    "description": "Monthly Financial Snapshot shows current values without showing variance vs prior month/target. Add delta indicators or a small trend to help users understand if values are improving or worsening.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Monthly Financial Snapshot panel",
    "effort": "small",
    "status": "pending",
    "notes": "Usability review on 2026-02-06: values are isolated without context."
  },
  {
    "id": 41,
    "category": "dashboard-fix",
    "title": "Family Essentials total lacks category breakdown",
    "description": "Family Essentials (Last Month) shows a single total with no category breakdown or drivers. Consider a small stacked bar or top categories list to explain the total.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Family Essentials panel",
    "effort": "small",
    "status": "pending",
    "notes": "Usability review on 2026-02-06."
  },
  {
    "id": 42,
    "category": "dashboard-fix",
    "title": "Data Freshness does not show timezone or refresh cadence",
    "description": "Data Freshness lists dates/times without indicating timezone or refresh cadence. Add timezone (e.g., local vs UTC) and a short note on refresh frequency so users can interpret staleness correctly.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Data Freshness panel",
    "effort": "tiny",
    "status": "pending",
    "notes": "Usability review on 2026-02-06."
  },
  {
    "id": 43,
    "category": "dashboard-fix",
    "title": "Executive Summary mixes multiple time bases in one sentence",
    "description": "Executive Summary combines latest closed month, a forecast for next month, and a review cadence in a single sentence, which is hard to parse. Split into labeled fields or separate lines with explicit time basis.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Executive Summary panel",
    "effort": "tiny",
    "status": "pending",
    "notes": "Usability review on 2026-02-06: multiple timeframes in one line."
  },
  {
    "id": 44,
    "category": "dashboard-fix",
    "title": "Savings & Expense Performance lacks targets/benchmarks",
    "description": "Savings Rate and Expense Ratio values appear without target ranges or benchmarks, making it unclear whether performance is good or bad. Add thresholds or contextual labels (e.g., 'Target > 10%').",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Savings & Expense Performance panel",
    "effort": "tiny",
    "status": "pending",
    "notes": "Usability review on 2026-02-06."
  },
  {
    "id": 45,
    "category": "dashboard-fix",
    "title": "Health & Risk KPIs mixes scores and counts without units",
    "description": "Health & Risk KPIs combines a score (Net Worth Health Score) and a count (Accounts At Risk) in the same table without units or definitions. Add units/definitions or split into separate panels so the metrics are comparable.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Health & Risk KPIs panel",
    "effort": "small",
    "status": "pending",
    "notes": "Usability review on 2026-02-06."
  },
  {
    "id": 46,
    "category": "dashboard-fix",
    "title": "Data Quality Callouts lacks remediation guidance",
    "description": "Callouts flag issues but do not indicate what action to take or where to drill down. Add short remediation guidance or explicit 'Next step' links to the relevant dashboards.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Data Quality Callouts panel",
    "effort": "small",
    "status": "pending",
    "notes": "Usability review on 2026-02-06."
  },
  {
    "id": 47,
    "category": "dashboard-fix",
    "title": "Expense Control Score lacks definition and scale",
    "description": "Expense Control Score is a single number with no scale or explanation. Add a description of how it is calculated and what range constitutes good vs bad.",
    "scope": "grafana/provisioning/dashboards/executive-dashboard.json; Expense Control Score panel",
    "effort": "tiny",
    "status": "pending",
    "notes": "Usability review on 2026-02-06."
  }
]
