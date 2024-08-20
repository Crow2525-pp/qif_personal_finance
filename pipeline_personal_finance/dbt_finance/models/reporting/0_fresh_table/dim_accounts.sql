with subquery as (
select  distinct
	account_name as account_code,
	TRIM(
		CASE 
		    WHEN account_name LIKE '%_Homeloan%' THEN SPLIT_PART(account_name, '_Homeloan', 1)
		    WHEN account_name LIKE '%_Offset%' THEN SPLIT_PART(account_name, '_Offset', 1)
		    ELSE SPLIT_PART(account_name, '_', 1)
		END
	    ) AS bank_name,
	TRIM(
		CASE
		    WHEN account_name LIKE '%_Homeloan%' THEN 'Homeloan'
		    WHEN account_name LIKE '%_Offset%' THEN 'Offset'
		    ELSE SPLIT_PART(SPLIT_PART(account_name, '_', 2), '_Transactions.qif', 1)
		END
	    ) AS account_name,
    date
	from {{ ref('reporting__fresh_table') }}
),
final as (
  select
    row_number() over() as surrogate_key,
    account_code,
    bank_name, 
    account_name,
    min(date) as start_date,
    case
      when CURRENT_DATE >= max(date) then '9999-12-31'
      else max(date)
    end as end_date
from
  subquery
group by
  account_code,
  account_name,
  bank_name
)


select * from final
