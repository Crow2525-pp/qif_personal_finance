-- Ensure Executive Dashboard net worth matches Household Net Worth for the latest complete month
WITH exec_latest AS (
  SELECT 
    dashboard_month,
    current_net_worth
  FROM {{ ref('rpt_executive_dashboard') }}
  ORDER BY dashboard_year DESC, dashboard_month_num DESC
  LIMIT 1
),
nw AS (
  SELECT 
    budget_year_month,
    net_worth
  FROM {{ ref('rpt_household_net_worth') }}
  WHERE budget_year_month = (SELECT dashboard_month FROM exec_latest)
)
SELECT *
FROM (
  SELECT 
    e.dashboard_month,
    e.current_net_worth            AS exec_net_worth,
    ROUND(n.net_worth, 0)          AS nw_net_worth
  FROM exec_latest e
  JOIN nw n ON n.budget_year_month = e.dashboard_month
 ) cmp
WHERE exec_net_worth != nw_net_worth
