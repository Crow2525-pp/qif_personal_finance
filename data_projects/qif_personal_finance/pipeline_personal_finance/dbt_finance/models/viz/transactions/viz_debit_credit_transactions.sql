SELECT 
    TO_CHAR(ft.transaction_date, 'YYYY-MM') AS year_month,
    ft.transaction_amount,
    ft.transaction_direction,
    da.account_key AS account_key,
    da.account_name,
    da.bank_name,
    dc.category,
    dc.level_2_subcategory AS subcategory,
    dc.store,
    dc.internal_indicator
FROM {{ ref('fct_transactions') }} AS ft
LEFT JOIN {{ ref('dim_categories') }} AS dc
    ON ft.category_key = dc.category_key
LEFT JOIN {{ ref('dim_accounts') }} AS da
    ON ft.account_key = da.account_key
