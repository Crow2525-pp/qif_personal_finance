# Family Finance Dashboard Roadmap

## Strategic Direction

The current dashboard suite provides comprehensive financial metrics but is optimized for detailed analysis rather than the quick, actionable insights needed by busy parents with three young children. The immediate priority is reducing the 38.7% uncategorized spend to under 15% so that category-level insights become trustworthy, then building family-specific views that surface childcare costs, grocery trends, and emergency fund progress prominently. Once the data foundation is solid, we'll add weekly pacing indicators and a simplified "Parent Dashboard" that answers "are we on track this week?" in under 30 seconds.

The second phase focuses on forward-looking features: upcoming recurring bills, seasonal expense preparation (school terms, holidays, sports registrations), and education savings goal tracking. Mobile dashboards will be enhanced with family-specific quick-glance panels so parents can check finances while managing morning routines. Throughout, the emphasis is on reducing cognitive load—surfacing only what matters this week rather than overwhelming with historical analysis.

---

## Concrete Tasks (Priority Order)

[
  {
    "id": 1,
    "category": "data-quality",
    "title": "Add top 20 uncategorized merchants to category mappings",
    "description": "Review the Top Uncategorized Merchants panel on Executive dashboard and add category mappings for the 20 highest-spend merchants to reduce uncategorized spend from 38.7% toward 15%",
    "scope": "seeds/category_mappings + dbt run",
    "effort": "small",
    "status": "in-progress",
    "notes": "Use scripts/categorize_transactions.py interactive tool. 19 patterns (1004 transactions) categorized in previous session."
  },
  {
    "id": 2,
    "category": "data-quality",
    "title": "Create childcare-specific subcategory",
    "description": "Add 'Childcare & Early Education' as a subcategory under Family & Kids with mappings for daycare centers, preschools, and babysitting services",
    "scope": "seeds/category_mappings + dbt model update",
    "effort": "small",
    "status": "pending",
    "notes": "Add subcategory mappings in banking_categories.csv with subcategory='Childcare & Early Education'"
  },
  {
    "id": 3,
    "category": "family-insights",
    "title": "Add 'Family Essentials' cost panel to Executive dashboard",
    "description": "Create a single stat row showing monthly totals for: Childcare, Groceries, Kids Activities, Family Medical. These are the non-negotiable costs parents need to see first",
    "scope": "Grafana Executive dashboard + new SQL panel",
    "effort": "medium",
    "status": "done",
    "notes": "Created rpt_family_essentials.sql model and added 'Family Essentials (Last Month)' stat panel to Executive dashboard"
  },
  {
    "id": 4,
    "category": "emergency-fund",
    "title": "Add emergency fund coverage panel to Executive dashboard",
    "description": "Calculate months of essential expenses covered by liquid assets (target: 3-6 months). Show as gauge with red/yellow/green zones",
    "scope": "Grafana panel + SQL calculation",
    "effort": "small",
    "status": "done",
    "notes": "Created rpt_emergency_fund_coverage.sql model and added gauge panel to Executive dashboard with red/orange/yellow/green thresholds at 0/1/3/6 months"
  },
  {
    "id": 5,
    "category": "weekly-pacing",
    "title": "Add 'Week-to-Date Spending Pace' panel",
    "description": "Show current week spending vs weekly budget target (monthly budget / weeks in month). Include 'days remaining' and 'daily budget remaining' for easy mental math",
    "scope": "New Grafana panel on Executive or new Weekly Review dashboard",
    "effort": "medium",
    "status": "done",
    "notes": "Created rpt_weekly_spending_pace.sql model and added 'Week-to-Date Spending Pace' stat panel to Executive dashboard showing weekly budget, spending, and daily budget remaining"
  },
  {
    "id": 6,
    "category": "family-insights",
    "title": "Create Grocery spending breakdown panel",
    "description": "Break down grocery spending by store (Coles, Woolworths, Aldi, etc.) with average basket size and visit frequency to identify shopping pattern opportunities",
    "scope": "Grafana Category Spending dashboard or Grocery dashboard",
    "effort": "small"
  },
  {
    "id": 7,
    "category": "upcoming-expenses",
    "title": "Add 'Bills Due Next 14 Days' panel",
    "description": "Surface recurring bills due in the next 2 weeks with amounts and due dates. Critical for cash flow planning around pay cycles",
    "scope": "New dbt model for recurring transaction detection + Grafana panel",
    "effort": "medium"
  },
  {
    "id": 8,
    "category": "mobile",
    "title": "Add 'This Week Summary' to mobile Executive Overview",
    "description": "Add compact panel showing: week spending vs pace, emergency fund months, and single biggest expense this week",
    "scope": "Grafana mobile Executive Overview dashboard",
    "effort": "small"
  },
  {
    "id": 9,
    "category": "data-quality",
    "title": "Add kids activities merchants to category mappings",
    "description": "Map swimming lessons, sports clubs, music classes, playgroups, and similar merchants to 'Kids Activities' subcategory",
    "scope": "seeds/category_mappings",
    "effort": "small"
  },
  {
    "id": 10,
    "category": "simplification",
    "title": "Create 'Parent Quick Check' dashboard",
    "description": "New single-page dashboard with only 6 panels: This Week Pace, Emergency Fund Months, Family Essentials Total, Biggest Unusual Expense, Uncategorized Count, Bills Due Soon",
    "scope": "New Grafana dashboard",
    "effort": "medium"
  },
  {
    "id": 11,
    "category": "savings-goals",
    "title": "Add education savings goal tracker",
    "description": "Track progress toward education fund goals (e.g., $X per child by school age). Show current balance, monthly contribution needed, and progress percentage",
    "scope": "Grafana Savings Analysis dashboard + goal configuration",
    "effort": "medium"
  },
  {
    "id": 12,
    "category": "family-insights",
    "title": "Add 'Cost Per Child' estimation panel",
    "description": "Divide Family & Kids category spending by number of children to show approximate monthly cost per child for budgeting discussions",
    "scope": "Grafana panel with configurable child count variable",
    "effort": "small"
  },
  {
    "id": 13,
    "category": "alerts",
    "title": "Add spending spike alert to Executive dashboard",
    "description": "Highlight when any category exceeds 150% of its 3-month average with the category name and overage amount prominently displayed",
    "scope": "Grafana conditional formatting + SQL",
    "effort": "small"
  },
  {
    "id": 14,
    "category": "seasonal",
    "title": "Add 'Seasonal Expense Preparation' panel",
    "description": "Show upcoming seasonal costs based on historical patterns: school term fees (Feb, Apr, Jul, Oct), Christmas (Nov-Dec), winter utilities (Jun-Aug), sports registration seasons",
    "scope": "New dbt model + Grafana panel",
    "effort": "medium"
  },
  {
    "id": 15,
    "category": "cash-flow",
    "title": "Add pay cycle cash flow projection",
    "description": "Project cash position at next pay date based on known bills and average daily discretionary spend. Answer: 'Will we make it to payday?'",
    "scope": "SQL model + Grafana panel",
    "effort": "medium"
  },
  {
    "id": 16,
    "category": "mobile",
    "title": "Add quick categorization link to mobile dashboards",
    "description": "Add deep link from mobile uncategorized count to Transaction Analysis filtered to uncategorized items for quick review during downtime",
    "scope": "Grafana mobile dashboard link configuration",
    "effort": "small"
  },
  {
    "id": 17,
    "category": "family-insights",
    "title": "Add 'Fixed vs Flexible' expense breakdown",
    "description": "Classify expenses as Fixed (mortgage, insurance, childcare) vs Flexible (dining, entertainment, shopping) to show actual discretionary budget available",
    "scope": "Category classification + Grafana panel",
    "effort": "medium"
  },
  {
    "id": 18,
    "category": "simplification",
    "title": "Add 'Top 3 Actions This Week' panel",
    "description": "Rule-based recommendations panel: e.g., 'Categorize 5 transactions', 'Grocery spend up 20% - check receipts', 'Transfer $X to emergency fund to hit 3-month target'",
    "scope": "SQL logic + Grafana panel on Parent Quick Check",
    "effort": "medium"
  },
  {
    "id": 19,
    "category": "data-quality",
    "title": "Add medical expense subcategories",
    "description": "Break down Health & Medical into: GP Visits, Pharmacy, Specialist, Hospital, Health Insurance to track kids' medical costs separately",
    "scope": "seeds/category_mappings + merchant classification",
    "effort": "small"
  },
  {
    "id": 20,
    "category": "reporting",
    "title": "Add monthly family finance summary text panel",
    "description": "Auto-generated plain English summary: 'In December, your family spent $X on essentials and $Y on discretionary items. Emergency fund covers N months. Biggest increase: Groceries (+$Z).'",
    "scope": "SQL text generation + Grafana text panel",
    "effort": "medium"
  }
]
