#!/bin/bash
set -e

# Create Grafana read-only user for dashboard access
# This script runs on first database initialization only

# Validate required environment variables
if [ -z "$GRAFANA_USER" ] || [ -z "$GRAFANA_PASSWORD" ]; then
    echo "ERROR: GRAFANA_USER and GRAFANA_PASSWORD must be set"
    exit 1
fi

# Escape single quotes in password for SQL
ESCAPED_PASSWORD="${GRAFANA_PASSWORD//\'/\'\'}"

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

    -- Grant read-only access to reporting schema
    GRANT USAGE ON SCHEMA reporting TO "${GRAFANA_USER}";
    GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO "${GRAFANA_USER}";
    ALTER DEFAULT PRIVILEGES IN SCHEMA reporting GRANT SELECT ON TABLES TO "${GRAFANA_USER}";
EOSQL

echo "Grafana user '${GRAFANA_USER}' configured with read-only access to reporting schema."
