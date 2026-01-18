[
  {
    "category": "feature",
    "description": "Standardize time framing and freshness indicators across core dashboards",
    "branch": "feature/time-framing-freshness",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_personal_finance",
    "steps": [
      "Add a visible 'data through' date and last refresh timestamp to Executive, Monthly Budget Summary, Cash Flow Analysis, Household Net Worth, and Savings Analysis",
      "Use a consistent default of most recent complete month with a quick toggle for YTD and trailing 12 months",
      "Label panels that use different time windows to avoid mixed-period interpretation"
    ],
    "passes": false,
    "notes": "Implemented in code; pending Grafana verification."
  },
  {
    "category": "feature",
    "description": "Add data-quality and categorization backlog callouts where decisions are made",
    "branch": "feature/data-quality-callouts",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-data-quality-callouts",
    "steps": [
      "Add a compact data quality panel (missing accounts, unmatched transfers, uncategorized %) to Executive, Cash Flow Analysis, Outflows Insights, and Transaction Analysis",
      "Surface a prioritized list of top uncategorized merchants with counts and total spend",
      "Link outflows reconciliation status to the related exception list"
    ],
    "passes": true,
    "notes": "PR #10 merged 2026-01-16. Deployed to production - Data Quality Callouts and Top Uncategorized Merchants panels verified on Executive dashboard"
  },
  {
    "category": "feature",
    "description": "Make variance drivers actionable in spending dashboards",
    "branch": "feature/variance-drivers",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-variance-drivers",
    "steps": [
      "Add MoM and YoY variance driver panels with top categories and the top 5 transactions per category",
      "Include a threshold filter (e.g., >10% and >$100) to reduce noise",
      "Apply to Category Spending Analysis, Outflows Insights, and Monthly Budget Summary"
    ],
    "passes": false,
    "notes": "Grafana review: variance driver panels not visible on Category Spending, Outflows Insights, or Monthly Budget Summary. Implemented in code; pending Grafana verification."
  },
  {
    "category": "feature",
    "description": "Add budget vs actual views to support monthly decision making",
    "branch": "feature/budget-vs-actual",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-budget-vs-actual",
    "steps": [
      "Introduce budget targets and variance deltas in Monthly Budget Summary",
      "Add a budget heatmap for top categories with over/under indicators",
      "Provide a short list of suggested adjustments for next month based on historical average"
    ],
    "passes": false,
    "notes": "Grafana review: Monthly Budget Summary lacks budget targets/variance, heatmap, and adjustment suggestions. Implemented in code; pending Grafana verification."
  },
  {
    "category": "feature",
    "description": "Improve cash flow guidance with specific, traceable recommendations",
    "branch": "feature/cash-flow-guidance",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-cash-flow-guidance",
    "steps": [
      "Connect cash flow recommendations to the underlying categories and transactions",
      "Add a panel showing recurring bills due next month and their projected impact",
      "Include a 'what changed since last month' summary with links to variance drivers"
    ],
    "passes": false,
    "notes": "Grafana review: Cash Flow Analysis missing recurring bills next month and 'what changed since last month' summary. Implemented in code; pending Grafana verification."
  },
  {
    "category": "feature",
    "description": "Strengthen transaction analysis with anomaly and review workflows",
    "branch": "feature/transaction-anomaly",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-transaction-anomaly",
    "steps": [
      "Add anomaly flags for unusually high transactions vs 12-month baseline",
      "Include a 'needs review' queue combining large, uncategorized, and new merchants",
      "Add quick filters for account, merchant, and category"
    ],
    "passes": false,
    "notes": "Implemented in code; pending Grafana verification."
  },
  {
    "category": "feature",
    "description": "Enhance savings dashboards with goal-based guidance",
    "branch": "feature/savings-goals",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-savings-goals",
    "steps": [
      "Add explicit savings goals and progress-to-goal tracking",
      "Show required monthly transfer to hit goal and impact on cash flow",
      "Surface savings rate benchmarks and a short action checklist"
    ],
    "passes": false,
    "notes": "Grafana review: Savings Analysis missing explicit goal progress, required monthly transfer, and action checklist. Implemented in code; pending Grafana verification."
  },
  {
    "category": "feature",
    "description": "Make net worth and mortgage dashboards more decision-friendly",
    "branch": "feature/net-worth-mortgage",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-net-worth-mortgage",
    "steps": [
      "Add a debt payoff sensitivity panel (extra payments vs payoff date)",
      "Break out asset allocation trends by account type over time",
      "Add a 'net worth change drivers' panel tied to account movements"
    ],
    "passes": false,
    "notes": "Grafana review: Net worth dashboard missing payoff sensitivity and net worth change drivers panels. Implemented in code; pending Grafana verification."
  },
  {
    "category": "feature",
    "description": "Reduce dashboard redundancy and improve navigation",
    "branch": "feature/dashboard-navigation",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-dashboard-navigation",
    "steps": [
      "Add cross-links from Executive to Cash Flow, Budget, Spending, Net Worth, and Savings dashboards",
      "Consolidate repeated panels (e.g., cash flow trends, savings rate) into a single authoritative source",
      "Document which dashboards are mobile-only vs full detail"
    ],
    "passes": false,
    "notes": "Grafana review: no cross-links/navigation improvements observed on Executive dashboard."
  },
  {
    "category": "feature",
    "description": "Upgrade specialized merchant dashboards to include decision context",
    "branch": "feature/merchant-dashboard-context",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-merchant-dashboard-context",
    "steps": [
      "Add budget targets and variance highlights to Grocery and Amazon dashboards",
      "Include a top 10 item or order category breakdown where data allows",
      "Add a 'switching opportunity' panel showing alternative retailers with lower average spend"
    ],
    "passes": false,
    "notes": "Grafana review: Amazon/Grocery dashboards missing budget variance highlights and switching opportunity panels; Amazon panels show No data/400 errors. Implemented in code; pending Grafana verification."
  },
  {
    "category": "feature",
    "description": "Add executive actionability and risk callouts to the Executive Financial Overview",
    "branch": "feature/executive-actionability",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-executive-actionability",
    "steps": [
      "Add a short 'Top 3 actions this month' panel tied to cash flow, savings, and spending drivers",
      "Surface threshold-based alerts (negative cash flow, expense ratio >100%, savings rate < target)",
      "Link each action to the underlying dashboard panel or category list"
    ],
    "passes": false,
    "notes": "Grafana review: Executive dashboard missing 'Top 3 actions' and threshold alert callouts/links."
  },
  {
    "category": "feature",
    "description": "Make Monthly Budget Summary a decision-ready budget cockpit",
    "branch": "feature/budget-cockpit",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-budget-cockpit",
    "steps": [
      "Add remaining-days pace tracker (daily spend target vs actual) for the current month",
      "Split spending into fixed vs discretionary with a variance rollup",
      "Add a short 'budget adjustments for next month' list based on recent overruns"
    ],
    "passes": false,
    "notes": "Grafana review: Monthly Budget Summary missing pace tracker, fixed vs discretionary rollup, and adjustment list. Implemented in code; pending Grafana verification."
  },
  {
    "category": "feature",
    "description": "Deepen Cash Flow Analysis with income timing and bill awareness",
    "branch": "feature/cash-flow-income-timing",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-cash-flow-income-timing",
    "steps": [
      "Add income source mix and timing distribution for the latest complete month",
      "Show upcoming recurring bills for the next 30 days with expected impact",
      "Annotate cash flow trend with the top 3 category drivers"
    ],
    "passes": false,
    "notes": "Grafana review: Cash Flow Analysis missing income timing mix, upcoming 30-day bills, and driver annotations."
  },
  {
    "category": "feature",
    "description": "Add merchant-level insights to Outflows Insights",
    "branch": "feature/outflows-merchant-insights",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-outflows-merchant-insights",
    "steps": [
      "Include top merchants by spend and month-over-month change",
      "Add subscription/recurring charge detection and cancellation candidates",
      "Highlight price changes for repeat merchants (average charge delta)"
    ],
    "passes": false,
    "notes": "Grafana review: Outflows Insights missing top merchants, subscription candidates, and price change panels. Implemented in code; pending Grafana verification."
  },
  {
    "category": "feature",
    "description": "Enhance Transaction Analysis with review and exception workflows",
    "branch": "feature/transaction-review-workflow",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-transaction-review-workflow",
    "steps": [
      "Add duplicate and reversal/chargeback flags to the review queue",
      "Group transactions by merchant with a trend sparkline and last purchase date",
      "Add quick actions for recategorize, mark transfer, and exclude from budget"
    ],
    "passes": false,
    "notes": "Grafana review: Transaction Analysis missing review workflow panels (duplicates/reversals/actions); some panels show No data."
  },
  {
    "category": "feature",
    "description": "Add goal-first guidance to Savings Analysis",
    "branch": "feature/savings-goal-guidance",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-savings-goal-guidance",
    "steps": [
      "Show target savings rate and progress-to-goal for each defined goal",
      "Calculate required monthly savings to hit each target date",
      "Add a simple 'top levers' checklist based on expense and income trends"
    ],
    "passes": false,
    "notes": "Grafana review: Savings Analysis missing goal-first guidance and top levers checklist."
  },
  {
    "category": "feature",
    "description": "Add allocation and liquidity context to Household Net Worth Analysis",
    "branch": "feature/net-worth-liquidity",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-net-worth-liquidity",
    "steps": [
      "Add asset allocation breakdown by account type and a drift indicator",
      "Show liquidity coverage (months of expenses covered by liquid assets)",
      "Add net worth change drivers with asset/liability deltas"
    ],
    "passes": false,
    "notes": "Grafana review: Net worth dashboard missing allocation drift and change driver panels. Implemented in code; pending Grafana verification."
  },
  {
    "category": "feature",
    "description": "Expand Category Spending Analysis with budget limits and drivers",
    "branch": "feature/category-spending-budget",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-category-spending-budget",
    "steps": [
      "Add budget targets and over/under variance per top category",
      "Show top transactions within each category to explain spikes",
      "Add an uncategorized bucket with a link to the review queue"
    ],
    "passes": false,
    "notes": "Grafana review: Category Spending Analysis missing budget variance per category and top transaction drilldowns."
  },
  {
    "category": "feature",
    "description": "Improve Expense Performance Analysis with targets and attribution",
    "branch": "feature/expense-performance-targets",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-expense-performance-targets",
    "steps": [
      "Add target expense-to-income ratio and highlight distance to target",
      "Attribute month-over-month expense changes to top 5 categories",
      "Add a rolling 3-month average baseline for context"
    ],
    "passes": false
  },
  {
    "category": "feature",
    "description": "Make Account Performance more actionable for cash management",
    "branch": "feature/account-performance-cash",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-account-performance-cash",
    "steps": [
      "Add cash buffer coverage (months of expenses) per account group",
      "Explain large balance changes with top transfer/transaction drivers",
      "Add interest rate and fee summary for key accounts"
    ],
    "passes": false
  },
  {
    "category": "feature",
    "description": "Add assumptions and sensitivity to the Financial Projections Dashboard",
    "branch": "feature/financial-projections-sensitivity",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-financial-projections-sensitivity",
    "steps": [
      "Document scenario assumptions (income, expense growth, savings rate) inline",
      "Add sensitivity sliders for income and expense changes with delta output",
      "Show projected vs actual gaps to calibrate forecasts"
    ],
    "passes": true
  },
  {
    "category": "feature",
    "description": "Turn Financial Reconciliation into an actionable fix list",
    "branch": "feature/reconciliation-fix-list",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-reconciliation-fix-list",
    "steps": [
      "Add direct links from failed checks to the offending accounts or categories",
      "Summarize top data-quality blockers impacting dashboards",
      "Add a 'fix order' list sorted by financial impact"
    ],
    "passes": false,
    "notes": "Grafana review: Financial Reconciliation dashboard does not show data-quality blockers or fix-order list. Implemented in code; pending Grafana verification."
  },
  {
    "category": "feature",
    "description": "Add payoff scenario planning to the Mortgage Payoff Dashboard",
    "branch": "feature/mortgage-payoff-scenarios",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-mortgage-payoff-scenarios",
    "steps": [
      "Add extra-payment scenarios with new payoff dates",
      "Show total interest saved for each scenario",
      "Include refinance rate comparison with break-even month"
    ],
    "passes": false
  },
  {
    "category": "feature",
    "description": "Improve long-horizon comparison dashboards with normalized context",
    "branch": "feature/long-horizon-normalized",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-long-horizon-normalized",
    "steps": [
      "Add inflation-adjusted values for year-over-year and four-year views",
      "Highlight top 3 drivers for income, expenses, and net worth changes",
      "Add a short narrative summary of wins, risks, and next actions"
    ],
    "passes": false,
    "notes": "Implemented in code; pending Grafana verification."
  },
  {
    "category": "feature",
    "description": "Bring mobile dashboards closer to full-dashboard utility",
    "branch": "feature/mobile-dashboard-utility",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-mobile-dashboard-utility",
    "steps": [
      "Add 'last updated' and 'data through' stamps on all mobile dashboards",
      "Add deep links to the related full dashboards for drilldown",
      "Surface a compact alerts panel (cash flow negative, overspending, low savings)"
    ],
    "passes": false
  },
  {
    "category": "feature",
    "description": "Add order-level context to Amazon and Grocery dashboards",
    "branch": "feature/amazon-grocery-order-context",
    "worktree": "C:/Users/p_pat/Documents/projects/qif_worktrees/feature-amazon-grocery-order-context",
    "steps": [
      "Show order count, average order value, and largest order for the period",
      "Split recurring/subscription vs one-off purchases",
      "Add a basket-size trend to spot price inflation or volume changes"
    ],
    "passes": true,
    "notes": "Grafana review: order-context panels present but showing No data/400 errors on Amazon dashboard; verify datasource/query."
  }
]
