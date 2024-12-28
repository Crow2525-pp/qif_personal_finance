-- transformation/trans_categories.sql

with transaction_data as (
    select * from {{ ref('transformation__append_accounts') }}
),

category_mappings as (
    select * from {{ ref('dim_category') }}
),

-- Join transactions with mappings and categorize them
categorised_transactions as (
    select
        t.*,
        -- Null Value means uncat
        cm.origin_key as category_foreign_key
    from transaction_data as t
    left join category_mappings as cm
        on
            upper(t.account_name) = upper(cm.account_name)
            and (
                -- First priority: from/to fields
                (
                    t.sender is not NULL
                    and t.recipient is not NULL
                    and (cm.sender is not NULL and cm.recipient is not NULL)
                    and upper(t.sender) = upper(cm.sender)
                    and upper(t.recipient) = upper(cm.recipient)
                )
                or
                -- Second priority: transaction type
                (
                    t.transaction_type is not NULL
                    and cm.transaction_type is not NULL
                    and upper(t.transaction_type) = upper(cm.transaction_type)
                )
                or
                -- Third priority: transaction description
                (
                    t.memo is not NULL
                    and cm.transaction_description is not NULL
                    and t.memo ilike concat('%', cm.transaction_description, '%')
                )
            )
)

select *
from categorised_transactions
