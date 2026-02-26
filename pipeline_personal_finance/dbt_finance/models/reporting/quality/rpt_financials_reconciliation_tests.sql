{{
  config(
    materialized='table',
    indexes=[
      {'columns': ['period_date'], 'unique': false},
      {'columns': ['domain'], 'unique': false},
      {'columns': ['test_name'], 'unique': false}
    ]
  )
}}

WITH params AS (
  SELECT
    COALESCE({{ var('recon_months_back', 24) }}, 24)::int AS months_back,
    COALESCE({{ var('recon_tolerance', 15000) }}, 15000)::numeric AS tol_abs,
    COALESCE({{ var('recon_tolerance_pct', 0.02) }}, 0.02)::numeric AS tol_pct
),

periods AS (
  SELECT DISTINCT period_date
  FROM {{ ref('viz_detailed_outflows_breakdown') }}
  WHERE period_date >= (DATE_TRUNC('month', CURRENT_DATE) - ((SELECT months_back FROM params) || ' months')::interval)
),

-- 1) Bring in existing Outflows recon tests
outflows_tests AS (
  SELECT
    period_date,
    'Outflows'::text AS domain,
    test_name,
    left_value,
    right_value,
    delta,
    pass,
    notes
  FROM {{ ref('rpt_outflows_reconciliation_tests') }}
  WHERE period_date IN (SELECT period_date FROM periods)
),

-- 2) Budget: derivations in rpt_monthly_budget_summary
mbs_base AS (
  SELECT 
    to_date(budget_year_month || '-01', 'YYYY-MM-DD') AS period_date,
    total_income,
    total_expenses,
    net_cash_flow,
    savings_rate_percent,
    expense_ratio_percent,
    mortgage_expenses,
    household_expenses,
    food_expenses,
    family_expenses
  FROM {{ ref('rpt_monthly_budget_summary') }}
  WHERE to_date(budget_year_month || '-01', 'YYYY-MM-DD') IN (SELECT period_date FROM periods)
),

budget_tests AS (
  SELECT 
    period_date,
    'Budget'::text AS domain,
    'savings_rate_derivation'::text AS test_name,
    savings_rate_percent                                  AS left_value,
    (CASE WHEN total_income > 0 THEN (net_cash_flow / total_income) ELSE 0 END) AS right_value,
    (savings_rate_percent - CASE WHEN total_income > 0 THEN (net_cash_flow / total_income) ELSE 0 END) AS delta,
    (ABS(savings_rate_percent - CASE WHEN total_income > 0 THEN (net_cash_flow / total_income) ELSE 0 END) <= (SELECT tol_pct FROM params)) AS pass,
    'savings_rate = net_cash_flow / total_income'::text AS notes
  FROM mbs_base
  UNION ALL
  SELECT 
    period_date,
    'Budget'::text AS domain,
    'expense_ratio_derivation'::text AS test_name,
    expense_ratio_percent AS left_value,
    (CASE WHEN total_income > 0 THEN (total_expenses / total_income) ELSE 0 END) AS right_value,
    (expense_ratio_percent - CASE WHEN total_income > 0 THEN (total_expenses / total_income) ELSE 0 END) AS delta,
    (ABS(expense_ratio_percent - CASE WHEN total_income > 0 THEN (total_expenses / total_income) ELSE 0 END) <= (SELECT tol_pct FROM params)) AS pass,
    'expense_ratio = total_expenses / total_income'::text AS notes
  FROM mbs_base
),

-- 3) Income/Expense totals: viz vs budget
viz_ie AS (
  SELECT 
    to_date(year_month || '-01', 'YYYY-MM-DD') AS period_date,
    income::numeric  AS viz_income,
    expense::numeric AS viz_expense
  FROM {{ ref('viz_income_vs_expense_by_month') }}
  WHERE to_date(year_month || '-01', 'YYYY-MM-DD') IN (SELECT period_date FROM periods)
),

ie_tests AS (
  SELECT 
    m.period_date,
    'IncomeExpense'::text AS domain,
    'viz_vs_budget_income'::text AS test_name,
    v.viz_income AS left_value,
    m.total_income AS right_value,
    (v.viz_income - m.total_income) AS delta,
    (ABS(v.viz_income - m.total_income) <= (SELECT tol_abs FROM params)) AS pass,
    'viz income equals budget total_income'::text AS notes
  FROM mbs_base m
  LEFT JOIN viz_ie v USING (period_date)
  UNION ALL
  SELECT 
    m.period_date,
    'IncomeExpense'::text AS domain,
    'viz_vs_budget_expense'::text AS test_name,
    v.viz_expense AS left_value,
    m.total_expenses AS right_value,
    (v.viz_expense - m.total_expenses) AS delta,
    (ABS(v.viz_expense - m.total_expenses) <= (SELECT tol_abs FROM params)) AS pass,
    'viz expense equals budget total_expenses'::text AS notes
  FROM mbs_base m
  LEFT JOIN viz_ie v USING (period_date)
),

-- 4) Cash flow net equals components
cf AS (
  SELECT 
    to_date(budget_year_month || '-01', 'YYYY-MM-DD') AS period_date,
    net_cash_flow::numeric AS net_cash_flow,
    (operating_inflows - operating_outflows)::numeric AS operating_cash_flow,
    financing_cash_flow::numeric AS financing_cash_flow,
    investing_cash_flow::numeric AS investing_cash_flow
  FROM {{ ref('rpt_cash_flow_analysis') }}
  WHERE to_date(budget_year_month || '-01', 'YYYY-MM-DD') IN (SELECT period_date FROM periods)
),

cashflow_tests AS (
  SELECT 
    period_date,
    'CashFlow'::text AS domain,
    'net_equals_components'::text AS test_name,
    net_cash_flow AS left_value,
    (operating_cash_flow + financing_cash_flow + investing_cash_flow) AS right_value,
    (net_cash_flow - (operating_cash_flow + financing_cash_flow + investing_cash_flow)) AS delta,
    (ABS(net_cash_flow - (operating_cash_flow + financing_cash_flow + investing_cash_flow)) <= (SELECT tol_abs FROM params)) AS pass,
    'net = operating + financing + investing (excl. internal transfers)'::text AS notes
  FROM cf
),

 -- 5) Executive vs MBS alignment
exec_latest AS (
  SELECT 
    to_date(dashboard_month || '-01', 'YYYY-MM-DD') AS period_date,
    monthly_savings_rate_percent_pct::numeric AS exec_savings_pct,
    expense_to_income_ratio_pct::numeric     AS exec_expense_pct
  FROM {{ ref('rpt_executive_dashboard') }}
  WHERE to_date(dashboard_month || '-01', 'YYYY-MM-DD') IN (SELECT period_date FROM periods)
),

exec_tests AS (
  SELECT 
    e.period_date,
    'Executive'::text AS domain,
    'savings_pct_matches_mbs'::text AS test_name,
    e.exec_savings_pct AS left_value,
    (m.savings_rate_percent * 100)::numeric AS right_value,
    (e.exec_savings_pct - (m.savings_rate_percent * 100)) AS delta,
    (ABS(e.exec_savings_pct - (m.savings_rate_percent * 100)) <= 0.1) AS pass,
    'exec savings % equals mbs savings_rate_percent*100'::text AS notes
  FROM exec_latest e
  JOIN mbs_base m USING (period_date)
  UNION ALL
  SELECT 
    e.period_date,
    'Executive'::text AS domain,
    'expense_pct_matches_mbs'::text AS test_name,
    e.exec_expense_pct AS left_value,
    (m.expense_ratio_percent * 100)::numeric AS right_value,
    (e.exec_expense_pct - (m.expense_ratio_percent * 100)) AS delta,
    (ABS(e.exec_expense_pct - (m.expense_ratio_percent * 100)) <= 0.1) AS pass,
    'exec expense % equals mbs expense_ratio_percent*100'::text AS notes
  FROM exec_latest e
  JOIN mbs_base m USING (period_date)
),

-- 10) Budget vs Fact (from fct_transactions_enhanced)
ft_monthly AS (
  SELECT 
    DATE_TRUNC('month', ft.transaction_date)::date AS period_date,
    SUM(CASE WHEN ft.is_income_transaction THEN ABS(ft.transaction_amount) ELSE 0 END)::numeric AS ft_income,
    SUM(CASE WHEN ft.transaction_amount < 0 AND NOT COALESCE(ft.is_internal_transfer, FALSE) AND NOT COALESCE(ft.is_financial_service, FALSE)
             THEN ABS(ft.transaction_amount) ELSE 0 END)::numeric AS ft_expenses
  FROM {{ ref('fct_transactions') }} ft
  GROUP BY 1
),

mbs_vs_fact_tests AS (
  SELECT 
    m.period_date,
    'Budget'::text AS domain,
    'mbs_income_matches_fact'::text AS test_name,
    m.total_income AS left_value,
    f.ft_income     AS right_value,
    (m.total_income - f.ft_income) AS delta,
    (ABS(m.total_income - f.ft_income) <= (SELECT tol_abs FROM params)) AS pass,
    'MBS total_income equals sum of fact income txns'::text AS notes
  FROM mbs_base m
  LEFT JOIN ft_monthly f USING (period_date)
  UNION ALL
  SELECT 
    m.period_date,
    'Budget'::text AS domain,
    'mbs_expenses_matches_fact'::text AS test_name,
    m.total_expenses AS left_value,
    f.ft_expenses    AS right_value,
    (m.total_expenses - f.ft_expenses) AS delta,
    (ABS(m.total_expenses - f.ft_expenses) <= (SELECT tol_abs FROM params)) AS pass,
    'MBS total_expenses equals sum of fact expenses excl. internal/fin services'::text AS notes
  FROM mbs_base m
  LEFT JOIN ft_monthly f USING (period_date)
  UNION ALL
  SELECT 
    m.period_date,
    'Budget'::text AS domain,
    'mbs_net_matches_fact'::text AS test_name,
    m.net_cash_flow AS left_value,
    (COALESCE(f.ft_income,0) - COALESCE(f.ft_expenses,0)) AS right_value,
    (m.net_cash_flow - (COALESCE(f.ft_income,0) - COALESCE(f.ft_expenses,0))) AS delta,
    (ABS(m.net_cash_flow - (COALESCE(f.ft_income,0) - COALESCE(f.ft_expenses,0))) <= (SELECT tol_abs FROM params)) AS pass,
    'MBS net_cash_flow equals (fact income − fact expenses)'::text AS notes
  FROM mbs_base m
  LEFT JOIN ft_monthly f USING (period_date)
),

-- 11) Uncategorized threshold on Outflows
uncat_threshold AS (
  SELECT 
    period_date,
    total_outflows,
    uncategorized,
    CASE WHEN total_outflows > 0 THEN (uncategorized / total_outflows) ELSE 0 END AS uncategorized_pct,
    COALESCE({{ var('uncategorized_max_pct', 0.20) }}, 0.20)::numeric AS max_pct
  FROM {{ ref('viz_detailed_outflows_breakdown') }}
),

uncat_tests AS (
  SELECT 
    period_date,
    'Outflows'::text AS domain,
    'uncategorized_pct_within_threshold'::text AS test_name,
    uncategorized_pct  AS left_value,
    max_pct            AS right_value,
    (uncategorized_pct - max_pct) AS delta,
    (uncategorized_pct <= max_pct) AS pass,
    'Uncategorized / total_outflows <= uncategorized_max_pct'::text AS notes
  FROM uncat_threshold
),

-- 6) Additional Budget integrity
mbs_more AS (
  SELECT 
    period_date,
    total_income,
    total_expenses,
    net_cash_flow
  FROM mbs_base
),

budget_more_tests AS (
  SELECT 
    period_date,
    'Budget'::text AS domain,
    'net_equals_income_minus_expenses'::text AS test_name,
    net_cash_flow                 AS left_value,
    (total_income - total_expenses) AS right_value,
    (net_cash_flow - (total_income - total_expenses)) AS delta,
    (ABS(net_cash_flow - (total_income - total_expenses)) <= (SELECT tol_abs FROM params)) AS pass,
    'net_cash_flow = total_income - total_expenses'::text AS notes
  FROM mbs_more
),

-- 7) Outflows vs Budget expenses alignment
outflows_vs_budget AS (
  SELECT 
    vdob.period_date,
    vdob.total_outflows::numeric AS viz_outflows,
    mbs.total_expenses::numeric  AS mbs_expenses
  FROM {{ ref('viz_detailed_outflows_breakdown') }} vdob
  JOIN mbs_base mbs ON mbs.period_date = vdob.period_date
),

outflows_budget_tests AS (
  SELECT 
    period_date,
    'Outflows'::text AS domain,
    'viz_outflows_match_budget_expenses'::text AS test_name,
    viz_outflows AS left_value,
    mbs_expenses AS right_value,
    (viz_outflows - mbs_expenses) AS delta,
    (ABS(viz_outflows - mbs_expenses) <= (SELECT tol_abs FROM params)) AS pass,
    'viz total_outflows equals MBS total_expenses'::text AS notes
  FROM outflows_vs_budget
),

-- 8) Cash flow ratios derivations
cashflow_ratio_tests AS (
  SELECT 
    cf.period_date,
    'CashFlow'::text AS domain,
    'outflow_to_inflow_ratio_derivation'::text AS test_name,
    cf.outflow_to_inflow_ratio AS left_value,
    CASE WHEN cf.total_inflows > 0 THEN (cf.total_outflows / cf.total_inflows) ELSE 0 END AS right_value,
    (cf.outflow_to_inflow_ratio - (CASE WHEN cf.total_inflows > 0 THEN (cf.total_outflows / cf.total_inflows) ELSE 0 END)) AS delta,
    (ABS(cf.outflow_to_inflow_ratio - (CASE WHEN cf.total_inflows > 0 THEN (cf.total_outflows / cf.total_inflows) ELSE 0 END)) <= (SELECT tol_pct FROM params)) AS pass,
    'outflow_to_inflow_ratio = total_outflows / total_inflows'::text AS notes
  FROM (
    SELECT 
      to_date(budget_year_month || '-01','YYYY-MM-DD') AS period_date,
      total_inflows::numeric AS total_inflows,
      total_outflows::numeric AS total_outflows,
      outflow_to_inflow_ratio::numeric AS outflow_to_inflow_ratio
    FROM {{ ref('rpt_cash_flow_analysis') }}
  ) cf
  UNION ALL
  SELECT 
    cf.period_date,
    'CashFlow'::text AS domain,
    'cash_flow_margin_derivation'::text AS test_name,
    cf.cash_flow_margin_percent AS left_value,
    CASE WHEN cf.total_inflows > 0 THEN (cf.net_cash_flow / cf.total_inflows) ELSE 0 END AS right_value,
    (cf.cash_flow_margin_percent - (CASE WHEN cf.total_inflows > 0 THEN (cf.net_cash_flow / cf.total_inflows) ELSE 0 END)) AS delta,
    (ABS(cf.cash_flow_margin_percent - (CASE WHEN cf.total_inflows > 0 THEN (cf.net_cash_flow / cf.total_inflows) ELSE 0 END)) <= (SELECT tol_pct FROM params)) AS pass,
    'cash_flow_margin = net_cash_flow / total_inflows'::text AS notes
  FROM (
    SELECT 
      to_date(budget_year_month || '-01','YYYY-MM-DD') AS period_date,
      total_inflows::numeric AS total_inflows,
      net_cash_flow::numeric AS net_cash_flow,
      cash_flow_margin_percent::numeric AS cash_flow_margin_percent
    FROM {{ ref('rpt_cash_flow_analysis') }}
  ) cf
),

-- 9) Net Worth equation + property present
networth_base AS (
  SELECT 
    to_date(budget_year_month || '-01','YYYY-MM-DD') AS period_date,
    total_assets::numeric AS total_assets,
    total_liabilities::numeric AS total_liabilities,
    net_worth::numeric AS net_worth
  FROM {{ ref('rpt_household_net_worth') }}
),

networth_tests AS (
  SELECT 
    period_date,
    'NetWorth'::text AS domain,
    'equation_assets_minus_liabilities'::text AS test_name,
    net_worth AS left_value,
    (total_assets - total_liabilities) AS right_value,
    (net_worth - (total_assets - total_liabilities)) AS delta,
    (ABS(net_worth - (total_assets - total_liabilities)) <= (SELECT tol_abs FROM params)) AS pass,
    'net_worth = total_assets - total_liabilities'::text AS notes
  FROM networth_base
),

property_presence_tests AS (
  SELECT 
    to_date(budget_year_month || '-01','YYYY-MM-DD') AS period_date,
    'NetWorth'::text AS domain,
    'ppor_property_all_months_positive'::text AS test_name,
    CASE WHEN MAX(end_of_month_balance)::numeric > 0 THEN 1 ELSE 0 END::numeric AS left_value,
    1::numeric AS right_value,
    CASE WHEN MAX(end_of_month_balance)::numeric > 0 THEN 0 ELSE -1 END::numeric AS delta,
    (MAX(end_of_month_balance)::numeric > 0) AS pass,
    'PPOR property valuation present and positive each month'::text AS notes
  FROM {{ ref('int_property_assets_monthly') }}
  GROUP BY budget_year_month
),

-- 12) YoY sanity checks (Budget)
yoy_bounds AS (
  SELECT 
    COALESCE({{ var('yoy_income_change_limit_pct', 1.0) }}, 1.0)::numeric   AS inc_lim,
    COALESCE({{ var('yoy_expense_change_limit_pct', 1.5) }}, 1.5)::numeric  AS exp_lim
),

yoy_mbs AS (
  SELECT 
    m.period_date,
    m.total_income,
    m.total_expenses,
    LAG(m.total_income, 12)  OVER (ORDER BY m.period_date) AS prev_income,
    LAG(m.total_expenses, 12) OVER (ORDER BY m.period_date) AS prev_expenses
  FROM mbs_base m
),

yoy_tests AS (
  SELECT 
    y.period_date,
    'Budget'::text AS domain,
    'yoy_income_within_bounds'::text AS test_name,
    CASE WHEN y.prev_income > 0 THEN ((y.total_income - y.prev_income) / y.prev_income) ELSE NULL END AS left_value,
    (SELECT inc_lim FROM yoy_bounds) AS right_value,
    CASE WHEN y.prev_income > 0 THEN (((y.total_income - y.prev_income) / y.prev_income) - (SELECT inc_lim FROM yoy_bounds)) ELSE NULL END AS delta,
    (CASE WHEN y.prev_income > 0 THEN (ABS((y.total_income - y.prev_income) / y.prev_income) <= (SELECT inc_lim FROM yoy_bounds)) ELSE TRUE END) AS pass,
    'YoY income change within limit (abs %)'::text AS notes
  FROM yoy_mbs y
  UNION ALL
  SELECT 
    y.period_date,
    'Budget'::text AS domain,
    'yoy_expenses_within_bounds'::text AS test_name,
    CASE WHEN y.prev_expenses > 0 THEN ((y.total_expenses - y.prev_expenses) / y.prev_expenses) ELSE NULL END AS left_value,
    (SELECT exp_lim FROM yoy_bounds) AS right_value,
    CASE WHEN y.prev_expenses > 0 THEN (((y.total_expenses - y.prev_expenses) / y.prev_expenses) - (SELECT exp_lim FROM yoy_bounds)) ELSE NULL END AS delta,
    (CASE WHEN y.prev_expenses > 0 THEN (ABS((y.total_expenses - y.prev_expenses) / y.prev_expenses) <= (SELECT exp_lim FROM yoy_bounds)) ELSE TRUE END) AS pass,
    'YoY expense change within limit (abs %)'::text AS notes
  FROM yoy_mbs y
),

-- 13) Transactions abs consistency
fact_abs_consistency AS (
  SELECT 
    DATE_TRUNC('month', transaction_date)::date AS period_date,
    COUNT(*) FILTER (WHERE transaction_amount_abs <> ABS(transaction_amount)::numeric) AS violations
  FROM {{ ref('fct_transactions') }}
  GROUP BY 1
),

fact_abs_tests AS (
  SELECT 
    f.period_date,
    'Fact'::text AS domain,
    'txn_amount_abs_consistency'::text AS test_name,
    f.violations::numeric AS left_value,
    0::numeric AS right_value,
    f.violations::numeric AS delta,
    (f.violations = 0) AS pass,
    'transaction_amount_abs should equal ABS(transaction_amount)'::text AS notes
  FROM fact_abs_consistency f
),

-- 14) Daily balances vs fact EOM balances
fact_eom AS (
  SELECT DISTINCT
    DATE_TRUNC('month', ft.transaction_date)::date AS period_date,
    ft.account_key,
    FIRST_VALUE(ft.account_balance) OVER (
      PARTITION BY DATE_TRUNC('month', ft.transaction_date), ft.account_key
      ORDER BY ft.transaction_date DESC
    )::numeric AS eom_balance
  FROM {{ ref('fct_transactions') }} ft
),

daily_eom AS (
  SELECT DISTINCT
    DATE_TRUNC('month', fdb.balance_date)::date AS period_date,
    fdb.account_key,
    FIRST_VALUE(fdb.daily_balance) OVER (
      PARTITION BY DATE_TRUNC('month', fdb.balance_date), fdb.account_key
      ORDER BY fdb.balance_date DESC
    )::numeric AS eom_daily_balance
  FROM {{ ref('fct_daily_balances') }} fdb
),

eom_reconciled AS (
  SELECT
    fe.period_date,
    fe.account_key,
    fe.eom_balance,
    de.eom_daily_balance
  FROM fact_eom fe
  JOIN daily_eom de
    ON fe.period_date = de.period_date
   AND fe.account_key = de.account_key
),

eom_tests AS (
  SELECT 
    period_date,
    'Balances'::text AS domain,
    'daily_eom_matches_fact_eom (sum across accounts)'::text AS test_name,
    SUM(eom_daily_balance) AS left_value,
    SUM(eom_balance)       AS right_value,
    (SUM(eom_daily_balance) - SUM(eom_balance)) AS delta,
    (ABS(SUM(eom_daily_balance) - SUM(eom_balance)) <= (SELECT tol_abs FROM params)) AS pass,
    'Sum of last daily balances equals fact EOM balances on common account-month pairs'::text AS notes
  FROM eom_reconciled
  GROUP BY period_date
),

-- 15) Outflows category alignment with MBS breakouts
category_alignment AS (
  SELECT 
    v.period_date,
    v.food_dining::numeric            AS viz_food,
    v.household_utilities::numeric    AS viz_household,
    v.housing_mortgage::numeric       AS viz_mortgage,
    v.family_kids::numeric            AS viz_family,
    m.food_expenses::numeric          AS mbs_food,
    m.household_expenses::numeric     AS mbs_household,
    m.mortgage_expenses::numeric      AS mbs_mortgage,
    m.family_expenses::numeric        AS mbs_family
  FROM {{ ref('viz_detailed_outflows_breakdown') }} v
  JOIN mbs_base m ON m.period_date = v.period_date
),

category_alignment_tests AS (
  SELECT period_date, 'Outflows'::text AS domain, 'cat_food_alignment'::text AS test_name,
         viz_food AS left_value, mbs_food AS right_value,
         (viz_food - mbs_food) AS delta,
         (ABS(viz_food - mbs_food) <= (SELECT tol_abs FROM params)) AS pass,
         'Food & Dining equals MBS food_expenses'::text AS notes
  FROM category_alignment
  UNION ALL
  SELECT period_date, 'Outflows', 'cat_household_alignment',
         viz_household, mbs_household,
         (viz_household - mbs_household),
         (ABS(viz_household - mbs_household) <= (SELECT tol_abs FROM params)),
         'Household & Utilities equals MBS household_expenses'
  FROM category_alignment
  UNION ALL
  SELECT period_date, 'Outflows', 'cat_mortgage_alignment',
         viz_mortgage, mbs_mortgage,
         (viz_mortgage - mbs_mortgage),
         (ABS(viz_mortgage - mbs_mortgage) <= (SELECT tol_abs FROM params)),
         'Housing & Mortgage equals MBS mortgage_expenses'
  FROM category_alignment
  UNION ALL
  SELECT period_date, 'Outflows', 'cat_family_alignment',
         viz_family, mbs_family,
         (viz_family - mbs_family),
         (ABS(viz_family - mbs_family) <= (SELECT tol_abs FROM params)),
         'Family & Kids equals MBS family_expenses'
  FROM category_alignment
),

-- 16) Property valuations monotonic (no decreases)
property_monotonic AS (
  SELECT 
    budget_year_month,
    to_date(budget_year_month || '-01','YYYY-MM-DD') AS period_date,
    end_of_month_balance AS val_mid,
    LAG(end_of_month_balance) OVER (ORDER BY to_date(budget_year_month || '-01','YYYY-MM-DD')) AS prev_val
  FROM {{ ref('int_property_assets_monthly') }}
),

property_monotonic_tests AS (
  SELECT 
    period_date,
    'NetWorth'::text AS domain,
    'ppor_property_non_decreasing'::text AS test_name,
    (val_mid - COALESCE(prev_val, val_mid)) AS left_value,
    0::numeric AS right_value,
    (val_mid - COALESCE(prev_val, val_mid)) AS delta,
    ((val_mid - COALESCE(prev_val, val_mid)) >= 0) AS pass,
    'Property valuation should not decrease month-over-month (midpoint)'::text AS notes
  FROM property_monotonic
),

-- 17) Savings/Expense ratios within plausible bounds
bounds AS (
  SELECT 
    COALESCE({{ var('savings_rate_min', -2.0) }}, -2.0)::numeric AS sr_min,
    COALESCE({{ var('savings_rate_max',  2.0) }},  2.0)::numeric AS sr_max,
    COALESCE({{ var('expense_ratio_min', 0.0) }}, 0.0)::numeric  AS er_min,
    COALESCE({{ var('expense_ratio_max', 5.0) }}, 5.0)::numeric  AS er_max
),

ratio_bounds_tests AS (
  SELECT 
    m.period_date,
    'Budget'::text AS domain,
    'savings_rate_within_bounds'::text AS test_name,
    m.savings_rate_percent AS left_value,
    NULL::numeric AS right_value,
    0::numeric AS delta,
    (m.savings_rate_percent BETWEEN (SELECT sr_min FROM bounds) AND (SELECT sr_max FROM bounds)) AS pass,
    'Savings rate in configured bounds'::text AS notes
  FROM mbs_base m
  UNION ALL
  SELECT 
    m.period_date,
    'Budget'::text AS domain,
    'expense_ratio_within_bounds'::text AS test_name,
    m.expense_ratio_percent AS left_value,
    NULL::numeric AS right_value,
    0::numeric AS delta,
    (m.expense_ratio_percent BETWEEN (SELECT er_min FROM bounds) AND (SELECT er_max FROM bounds)) AS pass,
    'Expense ratio in configured bounds'::text AS notes
  FROM mbs_base m
),

-- 18) Income Uncategorized threshold
income_uncat AS (
  SELECT 
    DATE_TRUNC('month', ft.transaction_date)::date AS period_date,
    SUM(CASE WHEN ft.is_income_transaction THEN ABS(ft.transaction_amount) ELSE 0 END)::numeric AS income_total,
    SUM(CASE WHEN ft.is_income_transaction AND dc.level_1_category = 'Uncategorized' THEN ABS(ft.transaction_amount) ELSE 0 END)::numeric AS income_uncat
  FROM {{ ref('fct_transactions') }} ft
  LEFT JOIN {{ ref('dim_categories') }} dc ON ft.category_key = dc.category_key
  GROUP BY 1
),

income_uncat_tests AS (
  SELECT 
    i.period_date,
    'Income'::text AS domain,
    'income_uncategorized_pct_within_threshold'::text AS test_name,
    CASE WHEN i.income_total > 0 THEN (i.income_uncat / i.income_total) ELSE 0 END AS left_value,
    COALESCE({{ var('income_uncategorized_max_pct', 0.05) }}, 0.05)::numeric AS right_value,
    CASE WHEN i.income_total > 0 THEN ((i.income_uncat / i.income_total) - COALESCE({{ var('income_uncategorized_max_pct', 0.05) }}, 0.05)::numeric) ELSE 0 END AS delta,
    (CASE WHEN i.income_total > 0 THEN ((i.income_uncat / i.income_total) <= COALESCE({{ var('income_uncategorized_max_pct', 0.05) }}, 0.05)::numeric) ELSE TRUE END) AS pass,
    'Income uncategorized share within threshold'::text AS notes
  FROM income_uncat i
)

SELECT * FROM outflows_tests
UNION ALL SELECT * FROM budget_tests
UNION ALL SELECT * FROM budget_more_tests
UNION ALL SELECT * FROM ie_tests
UNION ALL SELECT * FROM cashflow_tests
UNION ALL SELECT * FROM exec_tests
UNION ALL SELECT * FROM mbs_vs_fact_tests
UNION ALL SELECT * FROM uncat_tests
UNION ALL SELECT * FROM outflows_budget_tests
UNION ALL SELECT * FROM cashflow_ratio_tests
UNION ALL SELECT * FROM networth_tests
UNION ALL SELECT * FROM property_presence_tests
UNION ALL SELECT * FROM category_alignment_tests
UNION ALL SELECT * FROM property_monotonic_tests
UNION ALL SELECT * FROM ratio_bounds_tests
UNION ALL SELECT * FROM income_uncat_tests
UNION ALL SELECT * FROM yoy_tests
UNION ALL SELECT * FROM fact_abs_tests
UNION ALL SELECT * FROM eom_tests
ORDER BY period_date DESC, domain, test_name
