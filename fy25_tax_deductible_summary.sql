-- FY25 Tax Deductible Expenses Summary
-- Financial Year 2025: July 1, 2024 - June 30, 2025

WITH tax_deductible_transactions AS (
    SELECT
        t.transaction_date,
        t.transaction_memo,
        t.transaction_description,
        t.transaction_amount_abs AS amount,
        CASE
            -- Books and education
            WHEN t.transaction_memo ILIKE '%book%' OR t.transaction_description ILIKE '%book%' OR
                 t.transaction_memo ILIKE '%amazon%' OR t.transaction_description ILIKE '%amazon%'
                 THEN 'Books/Amazon (Review for Work Related)'

            -- Electricity
            WHEN t.transaction_memo ILIKE '%electric%' OR t.transaction_description ILIKE '%electric%' OR
                 t.transaction_memo ILIKE '%power%' OR t.transaction_memo ILIKE '%energy%' OR
                 t.transaction_memo ILIKE '%agl%' OR t.transaction_memo ILIKE '%origin%' OR
                 t.transaction_memo ILIKE '%globird%' OR t.transaction_memo ILIKE '%powershop%' OR
                 t.transaction_memo ILIKE '%simply energy%' OR t.transaction_memo ILIKE '%red energy%'
                 THEN 'Electricity (WFH 3 days/week)'

            -- Gas
            WHEN t.transaction_memo ILIKE '%gas%' OR t.transaction_description ILIKE '%gas%'
                 THEN 'Gas (WFH 3 days/week)'

            -- Internet
            WHEN t.transaction_memo ILIKE '%internet%' OR t.transaction_description ILIKE '%internet%' OR
                 t.transaction_memo ILIKE '%nbn%' OR t.transaction_memo ILIKE '%broadband%' OR
                 t.transaction_memo ILIKE '%superloop%' OR t.transaction_memo ILIKE '%aussie broadband%' OR
                 t.transaction_memo ILIKE '%telstra%internet%' OR t.transaction_memo ILIKE '%optus%internet%'
                 THEN 'Internet (WFH 3 days/week)'

            -- Phone/Mobile
            WHEN t.transaction_memo ILIKE '%mobile%' OR t.transaction_memo ILIKE '%phone%' OR
                 t.transaction_memo ILIKE '%telstra%' OR t.transaction_memo ILIKE '%optus%' OR
                 t.transaction_memo ILIKE '%vodafone%' OR t.transaction_memo ILIKE '%boost%' OR
                 t.transaction_memo ILIKE '%amaysim%'
                 THEN 'Phone/Mobile (WFH 3 days/week)'

            -- AI Subscriptions (ChatGPT, Claude)
            WHEN t.transaction_memo ILIKE '%chatgpt%' OR t.transaction_memo ILIKE '%openai%' OR
                 t.transaction_memo ILIKE '%chat gpt%' OR t.transaction_memo ILIKE '%gpt%' OR
                 t.transaction_memo ILIKE '%claude%' OR t.transaction_memo ILIKE '%anthropic%' OR
                 t.transaction_description ILIKE '%openai%' OR t.transaction_description ILIKE '%anthropic%'
                 THEN 'AI Subscription (Work Tools)'

            -- Solar (credit, might be relevant for offsetting)
            WHEN t.transaction_memo ILIKE '%solar%' OR t.transaction_description ILIKE '%solar%'
                 THEN 'Solar Credit'

            ELSE 'Other Potential Deduction'
        END AS tax_deduction_category,

        -- Calculate potential deduction (3 days WFH = 42.86% of utilities)
        CASE
            WHEN t.transaction_memo ILIKE '%electric%' OR t.transaction_memo ILIKE '%power%' OR
                 t.transaction_memo ILIKE '%gas%' OR t.transaction_memo ILIKE '%internet%' OR
                 t.transaction_memo ILIKE '%mobile%' OR t.transaction_memo ILIKE '%phone%' OR
                 t.transaction_memo ILIKE '%nbn%' OR t.transaction_memo ILIKE '%broadband%' OR
                 t.transaction_memo ILIKE '%telstra%' OR t.transaction_memo ILIKE '%optus%' OR
                 t.transaction_memo ILIKE '%agl%' OR t.transaction_memo ILIKE '%origin%' OR
                 t.transaction_memo ILIKE '%globird%' OR t.transaction_memo ILIKE '%superloop%'
                 THEN ROUND(t.transaction_amount_abs * 0.4286, 2)  -- 3/7 days
            ELSE t.transaction_amount_abs
        END AS potential_deduction_amount

    FROM reporting.fct_transactions_enhanced t

    WHERE t.transaction_date >= '2024-07-01'
      AND t.transaction_date <= '2025-06-30'
      AND t.transaction_direction = 'Debit'
      AND (
        -- Books/Education/Amazon
        t.transaction_memo ILIKE '%book%' OR t.transaction_description ILIKE '%book%' OR
        t.transaction_memo ILIKE '%amazon%' OR t.transaction_description ILIKE '%amazon%' OR

        -- Electricity providers
        t.transaction_memo ILIKE '%electric%' OR t.transaction_description ILIKE '%electric%' OR
        t.transaction_memo ILIKE '%power%' OR t.transaction_memo ILIKE '%energy%' OR
        t.transaction_memo ILIKE '%agl%' OR t.transaction_memo ILIKE '%origin%' OR
        t.transaction_memo ILIKE '%globird%' OR t.transaction_memo ILIKE '%powershop%' OR
        t.transaction_memo ILIKE '%simply energy%' OR t.transaction_memo ILIKE '%red energy%' OR

        -- Gas
        t.transaction_memo ILIKE '%gas%' OR t.transaction_description ILIKE '%gas%' OR

        -- Internet
        t.transaction_memo ILIKE '%internet%' OR t.transaction_description ILIKE '%internet%' OR
        t.transaction_memo ILIKE '%nbn%' OR t.transaction_memo ILIKE '%broadband%' OR
        t.transaction_memo ILIKE '%superloop%' OR t.transaction_memo ILIKE '%aussie broadband%' OR

        -- Phone/Mobile
        t.transaction_memo ILIKE '%mobile%' OR t.transaction_memo ILIKE '%phone%' OR
        t.transaction_memo ILIKE '%telstra%' OR t.transaction_memo ILIKE '%optus%' OR
        t.transaction_memo ILIKE '%vodafone%' OR t.transaction_memo ILIKE '%boost%' OR
        t.transaction_memo ILIKE '%amaysim%' OR

        -- AI Subscriptions
        t.transaction_memo ILIKE '%chatgpt%' OR t.transaction_memo ILIKE '%openai%' OR
        t.transaction_memo ILIKE '%chat gpt%' OR t.transaction_memo ILIKE '%gpt%' OR
        t.transaction_memo ILIKE '%claude%' OR t.transaction_memo ILIKE '%anthropic%' OR
        t.transaction_description ILIKE '%openai%' OR t.transaction_description ILIKE '%anthropic%' OR

        -- Solar
        t.transaction_memo ILIKE '%solar%' OR t.transaction_description ILIKE '%solar%'
      )
),

category_summary AS (
    SELECT
        tax_deduction_category,
        COUNT(*) as transaction_count,
        ROUND(SUM(amount), 2) as total_actual_amount,
        ROUND(SUM(potential_deduction_amount), 2) as total_potential_deduction,
        1 as sort_order
    FROM tax_deductible_transactions
    GROUP BY tax_deduction_category

    UNION ALL

    SELECT
        'TOTAL ALL CATEGORIES' as tax_deduction_category,
        COUNT(*) as transaction_count,
        ROUND(SUM(amount), 2) as total_actual_amount,
        ROUND(SUM(potential_deduction_amount), 2) as total_potential_deduction,
        2 as sort_order
    FROM tax_deductible_transactions
)

SELECT
    tax_deduction_category,
    transaction_count,
    total_actual_amount,
    total_potential_deduction
FROM category_summary
ORDER BY sort_order, total_potential_deduction DESC;
