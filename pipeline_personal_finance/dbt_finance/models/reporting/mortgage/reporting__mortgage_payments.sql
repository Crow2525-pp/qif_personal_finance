with grouped as (
select 
    to_char(date, 'YYYY-MM') as year_month,
    trans.amount_type,
    trans.account_foreign_key
   cat.category,
  cat.subcategory,
  cat.store,
  sum(amount) as amount
    from 
  reporting.reporting__fact_transactions as trans
  left join reporting.dim_category as cat
  on trans.catgeory_foriegn_key = cat.origin_key
  left join reporting.dim_account as acc
  on trans.account_foreign_key = acc.origin_key
  


)
