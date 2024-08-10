select
    a.date,
    a.memo,
    a.receipt,
    a.location,
    a.description_date,
    a.card_no,
    a.sender,
    a.recepient,
    a.transaction_description,
    a.transaction_type,
    a.amount,
    a.line_number,
    a.primary_key,
    a.account_name,
    a.adjusted_balance,
    a.balance as unadjusted_balance
from {{ ref("transformation__Adel_Homeloan_adjst_bal") }} as a

union

select
    b.date,
    b.memo,
    b.receipt,
    b.location,
    b.description_date,
    b.card_no,
    b.sender,
    b.recepient,
    b.transaction_description,
    b.transaction_type,
    b.amount,
    b.line_number,
    b.primary_key,
    b.account_name,
    b.adjusted_balance,
    b.balance as unadjusted_balance
from {{ ref("transformation__Adel_Offset_adjst_bal") }} as b

union

select
    c.date,
    c.memo,
    c.receipt,
    c.location,
    c.description_date,
    c.card_no,
    c.sender,
    c.recepient,
    c.transaction_description,
    c.transaction_type,
    c.amount,
    c.line_number,
    c.primary_key,
    c.account_name,
    c.adjusted_balance,
    c.balance as unadjusted_balance
from {{ ref("transformation__Ben_Homeloan_adjst_bal") }} as c

union

select
    d.date,
    d.memo,
    d.receipt,
    d.location,
    d.description_date,
    d.card_no,
    d.sender,
    d.recepient,
    d.transaction_description,
    d.transaction_type,
    d.amount,
    d.line_number,
    d.primary_key,
    d.account_name,
    d.adjusted_balance,
    d.balance as unadjusted_balance
from {{ ref("transformation__Ben_Offset_adjst_bal") }} as d

union

select
    e.date,
    e.memo,
    e.receipt,
    e.location,
    e.description_date,
    e.card_no,
    e.sender,
    e.recepient,
    e.transaction_description,
    e.transaction_type,
    e.amount,
    e.line_number,
    e.primary_key,
    e.account_name,
    e.adjusted_balance,
    e.balance as unadjusted_balance

from {{ ref("transformation__ING_bills_adjst_bal") }} as e

union

select
    f.date,
    f.memo,
    f.receipt,
    f.location,
    f.description_date,
    f.card_no,
    f.sender,
    f.recepient,
    f.transaction_description,
    f.transaction_type,
    f.amount,
    f.line_number,
    f.primary_key,
    f.account_name,
    f.adjusted_balance,
    f.balance as unadjusted_balance
from {{ ref("transformation__ING_countdown_adjst_bal") }} as f
/* TODO: Fix inconsistent case of FROM/TO */
