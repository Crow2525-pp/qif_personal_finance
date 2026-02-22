#!/bin/bash
set -e

# Create Grafana read-only user for dashboard access
# This script runs on first database initialization only

# Validate required environment variables
if [ -z "$GRAFANA_USER" ] || [ -z "$GRAFANA_PASSWORD" ] || [ -z "$DAGSTER_POSTGRES_USER" ] || [ -z "$DAGSTER_POSTGRES_PASSWORD" ]; then
    echo "ERROR: GRAFANA_USER/GRAFANA_PASSWORD and DAGSTER_POSTGRES_USER/DAGSTER_POSTGRES_PASSWORD must be set"
    exit 1
fi

# Escape single quotes in password for SQL
ESCAPED_PASSWORD="${GRAFANA_PASSWORD//\'/\'\'}"
ESCAPED_DAGSTER_PASSWORD="${DAGSTER_POSTGRES_PASSWORD//\'/\'\'}"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<EOSQL
    -- Create tablefunc extension for crosstab/pivot queries
    CREATE EXTENSION IF NOT EXISTS tablefunc;

    -- Create reporting schema if it doesn't exist
    CREATE SCHEMA IF NOT EXISTS reporting;

    -- Create Grafana user with properly quoted identifier and escaped password
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${GRAFANA_USER}') THEN
            CREATE USER "${GRAFANA_USER}" WITH PASSWORD '${ESCAPED_PASSWORD}';
            RAISE NOTICE 'Created user ${GRAFANA_USER}';
        ELSE
            ALTER USER "${GRAFANA_USER}" WITH PASSWORD '${ESCAPED_PASSWORD}';
            RAISE NOTICE 'Updated password for existing user ${GRAFANA_USER}';
        END IF;
    END
    \$\$;

    -- Create/rotate Dagster service role (application write role)
    DO \$\$
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${DAGSTER_POSTGRES_USER}') THEN
            CREATE USER "${DAGSTER_POSTGRES_USER}" WITH PASSWORD '${ESCAPED_DAGSTER_PASSWORD}';
            RAISE NOTICE 'Created user ${DAGSTER_POSTGRES_USER}';
        ELSE
            ALTER USER "${DAGSTER_POSTGRES_USER}" WITH PASSWORD '${ESCAPED_DAGSTER_PASSWORD}';
            RAISE NOTICE 'Updated password for existing user ${DAGSTER_POSTGRES_USER}';
        END IF;
    END
    \$\$;

    -- Ensure app schemas exist
    CREATE SCHEMA IF NOT EXISTS landing;
    CREATE SCHEMA IF NOT EXISTS staging;
    CREATE SCHEMA IF NOT EXISTS transformation;

    -- Transfer schema ownership to dagster service role for dbt DDL operations
    ALTER SCHEMA landing OWNER TO "${DAGSTER_POSTGRES_USER}";
    ALTER SCHEMA staging OWNER TO "${DAGSTER_POSTGRES_USER}";
    ALTER SCHEMA transformation OWNER TO "${DAGSTER_POSTGRES_USER}";
    ALTER SCHEMA reporting OWNER TO "${DAGSTER_POSTGRES_USER}";

    -- Lock down defaults and grants
    REVOKE ALL ON SCHEMA landing, staging, transformation, reporting FROM PUBLIC;
    REVOKE ALL ON ALL TABLES IN SCHEMA landing, staging, transformation, reporting FROM PUBLIC;
    REVOKE ALL ON ALL SEQUENCES IN SCHEMA landing, staging, transformation, reporting FROM PUBLIC;

    -- Dagster service role: writer across application schemas (no DELETE)
    GRANT USAGE, CREATE ON SCHEMA landing, staging, transformation, reporting TO "${DAGSTER_POSTGRES_USER}";
    GRANT SELECT, INSERT, UPDATE, TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA landing, staging, transformation, reporting TO "${DAGSTER_POSTGRES_USER}";
    REVOKE DELETE ON ALL TABLES IN SCHEMA landing, staging, transformation, reporting FROM "${DAGSTER_POSTGRES_USER}";
    GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA landing, staging, transformation, reporting TO "${DAGSTER_POSTGRES_USER}";

    -- Grafana user: dashboard reads + DELETE (per repository policy request)
    GRANT USAGE ON SCHEMA landing, staging, transformation, reporting TO "${GRAFANA_USER}";
    GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO "${GRAFANA_USER}";
    GRANT DELETE ON ALL TABLES IN SCHEMA landing, staging, transformation, reporting TO "${GRAFANA_USER}";
    REVOKE INSERT, UPDATE, TRUNCATE, REFERENCES, TRIGGER ON ALL TABLES IN SCHEMA landing, staging, transformation, reporting FROM "${GRAFANA_USER}";

    -- Future objects created by dagster service inherit the same policy
    ALTER DEFAULT PRIVILEGES FOR USER "${DAGSTER_POSTGRES_USER}" IN SCHEMA landing, staging, transformation, reporting
        GRANT SELECT, INSERT, UPDATE, TRUNCATE, REFERENCES, TRIGGER ON TABLES TO "${DAGSTER_POSTGRES_USER}";
    ALTER DEFAULT PRIVILEGES FOR USER "${DAGSTER_POSTGRES_USER}" IN SCHEMA landing, staging, transformation, reporting
        REVOKE DELETE ON TABLES FROM "${DAGSTER_POSTGRES_USER}";
    ALTER DEFAULT PRIVILEGES FOR USER "${DAGSTER_POSTGRES_USER}" IN SCHEMA landing, staging, transformation, reporting
        GRANT DELETE ON TABLES TO "${GRAFANA_USER}";
    ALTER DEFAULT PRIVILEGES FOR USER "${DAGSTER_POSTGRES_USER}" IN SCHEMA landing, staging, transformation, reporting
        GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO "${DAGSTER_POSTGRES_USER}";
    ALTER DEFAULT PRIVILEGES FOR USER "${DAGSTER_POSTGRES_USER}" IN SCHEMA reporting
        GRANT SELECT ON TABLES TO "${GRAFANA_USER}";
EOSQL

echo "Configured users: '${DAGSTER_POSTGRES_USER}' (application writer) and '${GRAFANA_USER}' (Grafana read-only)."
