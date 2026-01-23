{% macro create_fk_if_not_exists(table_relation, column_name, ref_relation, ref_column, constraint_name) %}
  {% if target.type != 'postgres' %}
    {{ return('') }}
  {% endif %}

  {% set sql %}
    DO $$
    BEGIN
      IF NOT EXISTS (
        SELECT 1
        FROM information_schema.table_constraints tc
        WHERE tc.constraint_type = 'FOREIGN KEY'
          AND tc.constraint_name = '{{ constraint_name }}'
          AND tc.table_schema = '{{ table_relation.schema }}'
          AND tc.table_name = '{{ table_relation.identifier }}'
      ) THEN
        ALTER TABLE {{ table_relation }}
          ADD CONSTRAINT {{ constraint_name }}
          FOREIGN KEY ({{ column_name }})
          REFERENCES {{ ref_relation }} ({{ ref_column }});
      END IF;
    END $$;
  {% endset %}

  {{ return(sql) }}
{% endmacro %}
