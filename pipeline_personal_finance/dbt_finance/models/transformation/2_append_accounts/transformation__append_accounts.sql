select 
a.date,
a.memo,
a.Receipt,
a.location,
a.Description_Date,
a.card_no,
a."From",
a."to",
a.Transaction_Description,
a.transaction_type,
a.amount,
a.line_number,
a.primary_key,
a.Account,
a.adjusted_balance,
a.balance as unadjusted_balance 
from {{ ref("transformation__Adel_Homeloan_adjst_bal") }} as a

union

select 
b.date,
b.memo,
b.Receipt,
b.location,
b.Description_Date,
b.card_no,
b."From",
b."to",
b.Transaction_Description,
b.transaction_type,
b.amount,
b.line_number,
b.primary_key,
b.Account,
b.adjusted_balance,
b.balance as unadjusted_balance 
from {{ ref("transformation__Adel_Offset_adjst_bal") }} as b

union

select 
c.date,
c.memo,
c.Receipt,
c.location,
c.Description_Date,
c.card_no,
c."From",
c."to",
c.Transaction_Description,
c.transaction_type,
c.amount,
c.line_number,
c.primary_key,
c.Account,
c.adjusted_balance,
c.balance as unadjusted_balance 
from {{ ref("transformation__Ben_Homeloan_adjst_bal") }} as c

union

select 
d.date,
d.memo,
d.Receipt,
d.location,
d.Description_Date,
d.card_no,
d."From",
d."to",
d.Transaction_Description,
d.transaction_type,
d.amount,
d.line_number,
d.primary_key,
d.Account,
d.adjusted_balance,
d.balance as unadjusted_balance 
from {{ ref("transformation__Ben_Offset_adjst_bal") }} as d

union

select 
e.date,
e.memo,
e.Receipt,
e.location,
e.Description_Date,
e.card_no,
e."From",
e."to",
e.Transaction_Description,
e.transaction_type,
e.amount,
e.line_number,
e.primary_key,
e.Account,
e.adjusted_balance,
e.balance as unadjusted_balance 

from {{ ref("transformation__ING_bills_adjst_bal") }} as e

union

select 
f.date,
f.memo,
f.Receipt,
f.location,
f.Description_Date,
f.card_no,
f."From",
f."To",
f.Transaction_Description,
f.transaction_type,
f.amount,
f.line_number,
f.primary_key,
f.Account,
f.adjusted_balance,
f.balance as unadjusted_balance 
from {{ ref("transformation__ING_countdown_adjst_bal") }} as f
/* TODO: Fix inconsistent case of FROM/TO */