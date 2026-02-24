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
