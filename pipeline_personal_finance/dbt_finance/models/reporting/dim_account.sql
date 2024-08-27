with subquery as (
select  distinct
	account_foreign_key as origin_key,
	TRIM(
		CASE 
		    WHEN account_foreign_key LIKE '%_Homeloan%' THEN SPLIT_PART(account_foreign_key, '_Homeloan', 1)
		    WHEN account_foreign_key LIKE '%_Offset%' THEN SPLIT_PART(account_foreign_key, '_Offset', 1)
		    ELSE SPLIT_PART(account_foreign_key, '_', 1)
		END
	    ) AS bank_name,
	TRIM(
		CASE
		    WHEN account_foreign_key LIKE '%_Homeloan%' THEN 'Homeloan'
		    WHEN account_foreign_key LIKE '%_Offset%' THEN 'Offset'
		    ELSE SPLIT_PART(SPLIT_PART(account_foreign_key, '_', 2), '_Transactions.qif', 1)
		END
	    ) AS account_name,
    cast(date as date) as date
	from {{ ref('reporting__fact_transactions') }}
),
final as (
  select
    row_number() over() as surrogate_key,
    origin_key,
    bank_name,
	account_name,
    min(date) as start_date,
  	max(date) as end_date
from
  subquery
group by
  origin_key,
  bank_name,
  account_name
)


select * from final
