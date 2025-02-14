WITH unified_accounts AS (
    {{ dbt_utils.union_relations(
        relations=[
            ref("transformation__Adel_Homeloan_adjst_bal"),
            ref("transformation__Adel_Offset_adjst_bal"),
            ref("transformation__Ben_Homeloan_adjst_bal"),
            ref("transformation__Ben_Offset_adjst_bal"),
            ref("transformation__ING_bills_adjst_bal"),
            ref("transformation__ING_countdown_adjst_bal")
        ]
    ) }}
)

SELECT *,
    transaction_balance AS unadjusted_balance
FROM unified_accounts
