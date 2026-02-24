DO $$
BEGIN
    IF :'dagster_user' IS NULL OR :'dagster_user' = '' THEN
        RAISE EXCEPTION 'dagster_user psql var is required';
    END IF;
    IF :'grafana_user' IS NULL OR :'grafana_user' = '' THEN
        RAISE EXCEPTION 'grafana_user psql var is required';
    END IF;
END
$$;

CREATE SCHEMA IF NOT EXISTS landing;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS transformation;
CREATE SCHEMA IF NOT EXISTS reporting;

DO $$
BEGIN
    EXECUTE format('ALTER SCHEMA landing OWNER TO %I', :'dagster_user');
    EXECUTE format('ALTER SCHEMA staging OWNER TO %I', :'dagster_user');
    EXECUTE format('ALTER SCHEMA transformation OWNER TO %I', :'dagster_user');
    EXECUTE format('ALTER SCHEMA reporting OWNER TO %I', :'dagster_user');
END
$$;

REVOKE ALL ON SCHEMA landing, staging, transformation, reporting FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA landing, staging, transformation, reporting FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA landing, staging, transformation, reporting FROM PUBLIC;

DO $$
BEGIN
    EXECUTE format('GRANT USAGE, CREATE ON SCHEMA landing, staging, transformation, reporting TO %I', :'dagster_user');
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA landing, staging, transformation, reporting TO %I', :'dagster_user');
    EXECUTE format('REVOKE DELETE ON ALL TABLES IN SCHEMA landing, staging, transformation, reporting FROM %I', :'dagster_user');
    EXECUTE format('GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA landing, staging, transformation, reporting TO %I', :'dagster_user');

    EXECUTE format('GRANT USAGE ON SCHEMA reporting TO %I', :'grafana_user');
    EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO %I', :'grafana_user');
    EXECUTE format('REVOKE INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA landing, staging, transformation, reporting FROM %I', :'grafana_user');

    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA landing, staging, transformation, reporting GRANT SELECT, INSERT, UPDATE, TRUNCATE, REFERENCES, TRIGGER ON TABLES TO %I', :'dagster_user', :'dagster_user');
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA landing, staging, transformation, reporting REVOKE DELETE ON TABLES FROM %I', :'dagster_user', :'dagster_user');
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA landing, staging, transformation, reporting GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO %I', :'dagster_user', :'dagster_user');
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA reporting GRANT SELECT ON TABLES TO %I', :'dagster_user', :'grafana_user');
END
$$;

DO $$
DECLARE
    obj record;
BEGIN
    FOR obj IN
        SELECT n.nspname AS schema_name, c.relname AS object_name, c.relkind AS relkind
        FROM pg_class c
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname IN ('landing', 'staging', 'transformation', 'reporting')
          AND c.relkind IN ('r', 'v', 'm', 'S', 'f', 'p')
    LOOP
        BEGIN
            IF obj.relkind = 'S' THEN
                EXECUTE format('ALTER SEQUENCE %I.%I OWNER TO %I', obj.schema_name, obj.object_name, :'dagster_user');
            ELSE
                EXECUTE format('ALTER TABLE %I.%I OWNER TO %I', obj.schema_name, obj.object_name, :'dagster_user');
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'Could not change owner for %.%: %', obj.schema_name, obj.object_name, SQLERRM;
        END;
    END LOOP;
END
$$;
