{% macro get_table_names() %}
    {% set results = run_query("SELECT table_name FROM information_schema.tables WHERE table_schema = 'main';") %}
  
    {% if execute %}
        {% set table_names = [] %}
        {% for row in results %}
            {{ table_names.append(row['table_name']) }}
        {% endfor %}
    
        {{ return(table_names) }}
    {% endif %}
{% endmacro %}

{% macro enforce_dagster_execution() %}
    {% set allow_direct = env_var('ALLOW_DIRECT_DBT', '') | lower %}
    {% set context = env_var('DBT_EXECUTION_CONTEXT', '') | lower %}

    {% if execute and target.name != 'local_duckdb' and context != 'dagster' and allow_direct != '1' and allow_direct != 'true' %}
        {{ exceptions.raise_compiler_error(
            "Direct dbt execution is blocked by default for this project. "
            ~ "Run via Dagster instead (preferred: `make dagster-run`). "
            ~ "If you must bypass Dagster, set ALLOW_DIRECT_DBT=1 explicitly."
        ) }}
    {% endif %}

    {{ return('select 1') }}
{% endmacro %}

{% macro create_fk_if_not_exists(source_relation, source_column, target_relation, target_column, constraint_name) %}
    {% if target.type == 'postgres' %}
        DO $$
        BEGIN
            IF NOT EXISTS (
                SELECT 1
                FROM pg_constraint c
                JOIN pg_class t ON t.oid = c.conrelid
                JOIN pg_namespace n ON n.oid = t.relnamespace
                WHERE c.conname = '{{ constraint_name }}'
                  AND n.nspname = '{{ source_relation.schema }}'
                  AND t.relname = '{{ source_relation.identifier }}'
            ) THEN
                ALTER TABLE {{ source_relation }}
                ADD CONSTRAINT {{ constraint_name }}
                FOREIGN KEY ({{ source_column }})
                REFERENCES {{ target_relation }} ({{ target_column }});
            END IF;
        END
        $$;
    {% endif %}
{% endmacro %}

{% macro metric_expense(exclude_mortgage=false, table_alias='ft', category_alias='dc') %}
    CASE
        WHEN COALESCE({{ table_alias }}.is_income_transaction, FALSE) THEN 0
        WHEN COALESCE({{ table_alias }}.is_internal_transfer, FALSE) THEN 0
        WHEN COALESCE({{ table_alias }}.is_financial_service, FALSE) THEN 0
        WHEN {{ exclude_mortgage }} AND COALESCE({{ category_alias }}.level_1_category, '') = 'Mortgage' THEN 0
        WHEN {{ table_alias }}.transaction_amount < 0 THEN ABS({{ table_alias }}.transaction_amount)
        ELSE 0
    END
{% endmacro %}

{% macro metric_interest_payment(table_alias='ft', category_alias='dc') %}
    CASE
        WHEN COALESCE({{ table_alias }}.is_internal_transfer, FALSE) THEN 0
        WHEN COALESCE({{ category_alias }}.level_1_category, '') <> 'Mortgage' THEN 0
        WHEN (
            UPPER(COALESCE({{ table_alias }}.transaction_type, '')) IN ('DEBIT INTEREST', 'INTEREST')
            OR LOWER(COALESCE({{ category_alias }}.level_2_subcategory, '')) LIKE '%interest%'
            OR LOWER(COALESCE({{ category_alias }}.level_3_store, '')) LIKE '%interest%'
        ) AND {{ table_alias }}.transaction_amount < 0
            THEN ABS({{ table_alias }}.transaction_amount)
        ELSE 0
    END
{% endmacro %}
