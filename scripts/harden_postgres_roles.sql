DO $$
BEGIN
    IF current_setting('app.dagster_user', true) IS NULL THEN
        RAISE EXCEPTION 'Set app.dagster_user before running (e.g., -c "SET app.dagster_user = ''dagster_service''")';
    END IF;
    IF current_setting('app.dagster_password', true) IS NULL THEN
        RAISE EXCEPTION 'Set app.dagster_password before running';
    END IF;
    IF current_setting('app.grafana_user', true) IS NULL THEN
        RAISE EXCEPTION 'Set app.grafana_user before running';
    END IF;
END
$$;

DO $$
DECLARE
    dagster_user text := current_setting('app.dagster_user');
    dagster_password text := current_setting('app.dagster_password');
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = dagster_user) THEN
        EXECUTE format('CREATE ROLE %I LOGIN PASSWORD %L', dagster_user, dagster_password);
    ELSE
        EXECUTE format('ALTER ROLE %I WITH LOGIN PASSWORD %L', dagster_user, dagster_password);
    END IF;
END
$$;

CREATE SCHEMA IF NOT EXISTS landing;
CREATE SCHEMA IF NOT EXISTS staging;
CREATE SCHEMA IF NOT EXISTS transformation;
CREATE SCHEMA IF NOT EXISTS reporting;

DO $$
DECLARE
    dagster_user text := current_setting('app.dagster_user');
BEGIN
    EXECUTE format('ALTER SCHEMA landing OWNER TO %I', dagster_user);
    EXECUTE format('ALTER SCHEMA staging OWNER TO %I', dagster_user);
    EXECUTE format('ALTER SCHEMA transformation OWNER TO %I', dagster_user);
    EXECUTE format('ALTER SCHEMA reporting OWNER TO %I', dagster_user);
END
$$;

REVOKE ALL ON SCHEMA landing, staging, transformation, reporting FROM PUBLIC;
REVOKE ALL ON ALL TABLES IN SCHEMA landing, staging, transformation, reporting FROM PUBLIC;
REVOKE ALL ON ALL SEQUENCES IN SCHEMA landing, staging, transformation, reporting FROM PUBLIC;

DO $$
DECLARE
    dagster_user text := current_setting('app.dagster_user');
    grafana_user text := current_setting('app.grafana_user');
BEGIN
    EXECUTE format('GRANT USAGE, CREATE ON SCHEMA landing, staging, transformation, reporting TO %I', dagster_user);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA landing, staging, transformation, reporting TO %I', dagster_user);
    EXECUTE format('REVOKE DELETE ON ALL TABLES IN SCHEMA landing, staging, transformation, reporting FROM %I', dagster_user);
    EXECUTE format('GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA landing, staging, transformation, reporting TO %I', dagster_user);

    EXECUTE format('GRANT USAGE ON SCHEMA landing, staging, transformation, reporting TO %I', grafana_user);
    EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO %I', grafana_user);
    EXECUTE format('GRANT DELETE ON ALL TABLES IN SCHEMA landing, staging, transformation, reporting TO %I', grafana_user);
    EXECUTE format('REVOKE INSERT, UPDATE, TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA landing, staging, transformation, reporting FROM %I', grafana_user);

    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA landing, staging, transformation, reporting GRANT SELECT, INSERT, UPDATE, TRUNCATE, REFERENCES, TRIGGER ON TABLES TO %I', dagster_user, dagster_user);
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA landing, staging, transformation, reporting REVOKE DELETE ON TABLES FROM %I', dagster_user, dagster_user);
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA landing, staging, transformation, reporting GRANT DELETE ON TABLES TO %I', dagster_user, grafana_user);
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA landing, staging, transformation, reporting GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO %I', dagster_user, dagster_user);
    EXECUTE format('ALTER DEFAULT PRIVILEGES FOR ROLE %I IN SCHEMA reporting GRANT SELECT ON TABLES TO %I', dagster_user, grafana_user);
END
$$;

DO $$
DECLARE
    dagster_user text := current_setting('app.dagster_user');
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
                EXECUTE format('ALTER SEQUENCE %I.%I OWNER TO %I', obj.schema_name, obj.object_name, dagster_user);
            ELSIF obj.relkind IN ('r', 'p') THEN
                EXECUTE format('ALTER TABLE %I.%I OWNER TO %I', obj.schema_name, obj.object_name, dagster_user);
            ELSE
                EXECUTE format('ALTER TABLE %I.%I OWNER TO %I', obj.schema_name, obj.object_name, dagster_user);
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'Could not change owner for %.%: %', obj.schema_name, obj.object_name, SQLERRM;
        END;
    END LOOP;
END
$$;
