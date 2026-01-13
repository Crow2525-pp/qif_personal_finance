{#-
  Utility macros for common patterns across dbt models
  ================================================

  This file contains reusable macros for:
  - Date/period transformations
  - Transaction filtering
  - Memo normalization and selection
  - Priority bucketing for review views
  - Category suggestions
-#}

{#- ========================================
    DATE / PERIOD MACROS
======================================== -#}

{% macro month_period_fields(date_expr, year_month_alias='year_month', period_alias='period_date') %}
{#- Generate common month period fields from a date expression
    Args:
      date_expr: The date column or expression
      year_month_alias: Alias for the YYYY-MM text field (default: 'year_month')
      period_alias: Alias for the period_date field (default: 'period_date')
    Returns: Two columns - period_date and year_month
-#}
    DATE_TRUNC('month', {{ date_expr }})::date AS {{ period_alias }},
    TO_CHAR({{ date_expr }}, 'YYYY-MM') AS {{ year_month_alias }}
{% endmacro %}


{#- ========================================
    TRANSACTION FILTER MACROS
======================================== -#}

{% macro expense_outflow_filter(amount_col='transaction_amount', internal_flag_col='is_internal_transfer', table_alias='') %}
{#- Standard filter for expense/outflow transactions
    Args:
      amount_col: Name of the amount column (default: 'transaction_amount')
      internal_flag_col: Name of the internal transfer flag (default: 'is_internal_transfer')
      table_alias: Optional table alias prefix
    Returns: Boolean expression for outflow filtering
-#}
    {% set prefix = table_alias ~ '.' if table_alias else '' %}
    {{ prefix }}{{ amount_col }} < 0
    AND NOT COALESCE({{ prefix }}{{ internal_flag_col }}, FALSE)
{% endmacro %}


{% macro is_expense_transaction(table_alias='') %}
{#- Check if a transaction qualifies as an expense (uses fact table columns)
    Returns: Boolean expression
-#}
    {% set prefix = table_alias ~ '.' if table_alias else '' %}
    NOT COALESCE({{ prefix }}is_internal_transfer, FALSE)
    AND NOT COALESCE({{ prefix }}is_income_transaction, FALSE)
    AND {{ prefix }}transaction_amount < 0
{% endmacro %}


{#- ========================================
    TRANSACTION DIRECTION MACROS
======================================== -#}

{% macro transaction_direction(amount_expr) %}
{#- Derive transaction direction (Debit/Credit/Zero) from amount
    Args:
      amount_expr: The amount column or expression
    Returns: CASE expression yielding 'Debit', 'Credit', or 'Zero'
-#}
    CASE
        WHEN {{ amount_expr }} > 0 THEN 'Debit'
        WHEN {{ amount_expr }} < 0 THEN 'Credit'
        ELSE 'Zero'
    END
{% endmacro %}


{#- ========================================
    EXPENSE GROUPING MACROS
======================================== -#}

{% macro expense_group_from_level1(level_1_category_col='level_1_category', table_alias='') %}
{#- Map level_1_category to expense groups for outflow analysis
    Args:
      level_1_category_col: Name of the level_1_category column
      table_alias: Optional table alias prefix
    Returns: CASE expression mapping to expense groups
-#}
    {% set prefix = table_alias ~ '.' if table_alias else '' %}
    CASE
        WHEN {{ prefix }}{{ level_1_category_col }} = 'Mortgage' THEN 'Mortgage & Housing'
        WHEN {{ prefix }}{{ level_1_category_col }} = 'Bank Transaction' THEN 'Bank Fees'
        WHEN {{ prefix }}{{ level_1_category_col }} = 'Uncategorized' THEN 'Uncategorized'
        WHEN {{ prefix }}{{ level_1_category_col }} IN ('Car', 'Transport') THEN 'Transport'
        WHEN {{ prefix }}{{ level_1_category_col }} IN ('Health', 'Beauty') THEN 'Health & Beauty'
        WHEN {{ prefix }}{{ level_1_category_col }} IN ('Food', 'Dining', 'Groceries') THEN 'Food & Dining'
        WHEN {{ prefix }}{{ level_1_category_col }} IN ('Entertainment', 'Subscription') THEN 'Entertainment'
        WHEN {{ prefix }}{{ level_1_category_col }} IN ('Utilities', 'Bills') THEN 'Utilities & Bills'
        WHEN {{ prefix }}{{ level_1_category_col }} = 'Salary' THEN 'Income'
        ELSE 'Other Expenses'
    END
{% endmacro %}


{#- ========================================
    PRIORITY BUCKETING MACROS
======================================== -#}

{% macro review_priority_bucket(amount_expr) %}
{#- Generate priority bucket number for uncategorized review
    Args:
      amount_expr: The absolute amount expression
    Returns: Integer priority (1 = highest, 5 = lowest)
-#}
    CASE
        WHEN {{ amount_expr }} >= 1000 THEN 1
        WHEN {{ amount_expr }} >= 500 THEN 2
        WHEN {{ amount_expr }} >= 200 THEN 3
        WHEN {{ amount_expr }} >= 100 THEN 4
        ELSE 5
    END
{% endmacro %}


{% macro review_priority_label(priority_expr) %}
{#- Generate human-readable priority label from priority bucket
    Args:
      priority_expr: The priority number (1-5)
    Returns: Labeled priority string with emoji
-#}
    CASE
        WHEN {{ priority_expr }} = 1 THEN '🔴 HIGH ($1000+)'
        WHEN {{ priority_expr }} = 2 THEN '🟠 MEDIUM ($500-$999)'
        WHEN {{ priority_expr }} = 3 THEN '🟡 MODERATE ($200-$499)'
        WHEN {{ priority_expr }} = 4 THEN '🟢 LOW ($100-$199)'
        ELSE '⚪ MINOR (<$100)'
    END
{% endmacro %}


{#- ========================================
    MEMO HANDLING MACROS
======================================== -#}

{% macro best_memo(description_col='transaction_description', memo_col='transaction_memo', table_alias='') %}
{#- Select the best memo between description and memo fields
    Prefers the longer non-empty value, falls back to 'NO_MEMO'
    Args:
      description_col: Name of the description column
      memo_col: Name of the memo column
      table_alias: Optional table alias prefix
    Returns: COALESCE expression selecting best memo
-#}
    {% set prefix = table_alias ~ '.' if table_alias else '' %}
    COALESCE(
        CASE
            WHEN LENGTH(TRIM(COALESCE({{ prefix }}{{ description_col }}, ''))) > LENGTH(TRIM(COALESCE({{ prefix }}{{ memo_col }}, '')))
            THEN {{ prefix }}{{ description_col }}
            ELSE {{ prefix }}{{ memo_col }}
        END,
        'NO_MEMO'
    )
{% endmacro %}


{% macro normalize_memo(memo_expr) %}
{#- Normalize a memo field for pattern matching
    - Converts to uppercase
    - Removes receipt numbers, dates, card numbers
    - Removes non-alphanumeric characters
    Args:
      memo_expr: The memo expression to normalize
    Returns: Normalized uppercase text
-#}
    UPPER(
        REGEXP_REPLACE(
            REGEXP_REPLACE(
                REGEXP_REPLACE(
                    REGEXP_REPLACE(
                        COALESCE({{ memo_expr }}, ''),
                        'Receipt\\s+[0-9]+', ' ', 'gi'
                    ),
                    'Date\\s+\\d{2}\\s+[A-Za-z]{3}\\s+\\d{4}', ' ', 'gi'
                ),
                'Card\\s+[\\dx]+', ' ', 'gi'
            ),
            '[^A-Za-z0-9\\s]', ' ', 'g'
        )
    )
{% endmacro %}


{#- ========================================
    CATEGORY SUGGESTION MACROS
======================================== -#}

{% macro suggested_category_hint(memo_normalized_expr) %}
{#- Generate category hints based on normalized memo patterns
    Args:
      memo_normalized_expr: The normalized (uppercase) memo expression
    Returns: Category hint string
-#}
    CASE
        {# Car & Transport #}
        WHEN {{ memo_normalized_expr }} ILIKE '%SAWMAN%' OR {{ memo_normalized_expr }} ILIKE '%EXCEL%' OR {{ memo_normalized_expr }} ILIKE '%RACV%' THEN 'CAR_MAINTENANCE'
        WHEN {{ memo_normalized_expr }} ILIKE '%PETROLEUM%' OR {{ memo_normalized_expr }} ILIKE '%FUEL%' OR {{ memo_normalized_expr }} ILIKE '%BP%' OR {{ memo_normalized_expr }} ILIKE '%SHELL%' OR {{ memo_normalized_expr }} ILIKE '%AMPOL%' OR {{ memo_normalized_expr }} ILIKE '%CALTEX%' THEN 'FUEL'

        {# Health & Beauty #}
        WHEN {{ memo_normalized_expr }} ILIKE '%MECCA%' OR {{ memo_normalized_expr }} ILIKE '%HAIR%' OR {{ memo_normalized_expr }} ILIKE '%BEAUTY%' THEN 'BEAUTY'
        WHEN {{ memo_normalized_expr }} ILIKE '%BODY FIT%' OR {{ memo_normalized_expr }} ILIKE '%GYM%' OR {{ memo_normalized_expr }} ILIKE '%FITNESS%' THEN 'FITNESS'
        WHEN {{ memo_normalized_expr }} ILIKE '%CHEMIST%' OR {{ memo_normalized_expr }} ILIKE '%PHARMACY%' THEN 'PHARMACY'

        {# Food & Dining #}
        WHEN {{ memo_normalized_expr }} ILIKE '%COLES%' OR {{ memo_normalized_expr }} ILIKE '%WOOLWORTH%' OR {{ memo_normalized_expr }} ILIKE '%ALDI%' THEN 'GROCERIES'
        WHEN {{ memo_normalized_expr }} ILIKE '%DREAM CAKE%' OR {{ memo_normalized_expr }} ILIKE '%CAKE%' OR {{ memo_normalized_expr }} ILIKE '%BAKERY%' THEN 'BAKERY_TREATS'
        WHEN {{ memo_normalized_expr }} ILIKE '%MCDONALD%' OR {{ memo_normalized_expr }} ILIKE '%CAFE%' OR {{ memo_normalized_expr }} ILIKE '%RESTAURANT%' OR {{ memo_normalized_expr }} ILIKE '%SUSHI%' OR {{ memo_normalized_expr }} ILIKE '%DELI%' OR {{ memo_normalized_expr }} ILIKE '%HOTEL%' THEN 'FOOD_DINING'
        WHEN {{ memo_normalized_expr }} ILIKE '%OTHER BROTHER%' OR {{ memo_normalized_expr }} ILIKE '%COFFEE%' THEN 'COFFEE'

        {# Shopping & Retail #}
        WHEN {{ memo_normalized_expr }} ILIKE '%BUNNINGS%' OR {{ memo_normalized_expr }} ILIKE '%HARDWARE%' THEN 'HOME_IMPROVEMENT'
        WHEN {{ memo_normalized_expr }} ILIKE '%AMAZON%' OR {{ memo_normalized_expr }} ILIKE '%EBAY%' THEN 'ONLINE_SHOPPING'
        WHEN {{ memo_normalized_expr }} ILIKE '%DREAM CARS%' THEN 'TOYS_HOBBIES'

        {# Professional Services #}
        WHEN {{ memo_normalized_expr }} ILIKE '%O RAFFERTY%' OR {{ memo_normalized_expr }} ILIKE '%RAFFERTY%' THEN 'PROFESSIONAL_SERVICES'

        {# Transfers & Payments #}
        WHEN {{ memo_normalized_expr }} ILIKE '%OSKO%' OR {{ memo_normalized_expr }} ILIKE '%PATTERSON%' OR {{ memo_normalized_expr }} ILIKE '%TRANSFER%' THEN 'INTERNAL_TRANSFER'
        WHEN {{ memo_normalized_expr }} ILIKE '%DIRECT DEBIT%' AND {{ memo_normalized_expr }} NOT ILIKE '%BODY FIT%' THEN 'UNIDENTIFIED_DIRECT_DEBIT'

        {# Utilities & Services #}
        WHEN {{ memo_normalized_expr }} ILIKE '%UTIL%' OR {{ memo_normalized_expr }} ILIKE '%ELECTRIC%' OR {{ memo_normalized_expr }} ILIKE '%GAS%' OR {{ memo_normalized_expr }} ILIKE '%WATER%' THEN 'UTILITIES'
        WHEN {{ memo_normalized_expr }} ILIKE '%NETFLIX%' OR {{ memo_normalized_expr }} ILIKE '%SPOTIFY%' OR {{ memo_normalized_expr }} ILIKE '%SUBSCRIPTION%' THEN 'SUBSCRIPTION'
        WHEN {{ memo_normalized_expr }} ILIKE '%INSURANCE%' THEN 'INSURANCE'

        ELSE 'NEEDS_MANUAL_REVIEW'
    END
{% endmacro %}
