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
