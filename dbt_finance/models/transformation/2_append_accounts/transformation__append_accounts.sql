select date,
memo,
Receipt,
location,
Description_Date,
card_no,
"from",
"to",
Transaction_Description,
transaction_type,
amount,
line_number,
composite_key,
Account,
adjusted_balance,
balance as unadjusted_balance 
from {{ ref("transformation__Adel_Homeloan_adjst_bal") }}

union

select 
date,
memo,
Receipt,
location,
Description_Date,
card_no,
"from",
"to",
Transaction_Description,
transaction_type,
amount,
line_number,
composite_key,
Account,
adjusted_balance,
balance as unadjusted_balance 
from {{ ref("transformation__Adel_Offset_adjst_bal") }}

union

select date,
memo,
Receipt,
location,
Description_Date,
card_no,
"from",
"to",
Transaction_Description,
transaction_type,
amount,
line_number,
composite_key,
Account,
adjusted_balance,
balance as unadjusted_balance 
from {{ ref("transformation__Ben_Homeloan_adjst_bal") }}

union

select 
date,
memo,
Receipt,
location,
Description_Date,
card_no,
"from",
"to",
Transaction_Description,
transaction_type,
amount,
line_number,
composite_key,
Account,
adjusted_balance,
balance as unadjusted_balance 
from {{ ref("transformation__Ben_Offset_adjst_bal") }}

union

select 
date,
memo,
Receipt,
location,
Description_Date,
card_no,
"from",
"to",
Transaction_Description,
transaction_type,
amount,
line_number,
composite_key,
Account,
adjusted_balance,
balance as unadjusted_balance 

from {{ ref("transformation__ING_bills_adjst_bal") }}

union

select 
date,
memo,
Receipt,
location,
Description_Date,
card_no,
"from",
"to",
Transaction_Description,
transaction_type,
amount,
line_number,
composite_key,
Account,
adjusted_balance,
balance as unadjusted_balance 
from {{ ref("transformation__ING_countdown_adjst_bal") }}
