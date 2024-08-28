#!/bin/bash
set -e

# Call default entrypoint to handle the database initialization
/usr/local/bin/docker-entrypoint.sh postgres &

# Wait for PostgreSQL to start and be ready for connections
echo "Waiting for PostgreSQL to become active..."
until pg_isready -h localhost -p 5432 -U "${POSTGRES_USER}"; do
    echo "localhost:5432 - no response"
    sleep 1
done

echo "PostgreSQL is active."

echo "Using GRAFANA_USER: ${GRAFANA_USER} with GRAFANA_PASSWORD: ${GRAFANA_PASSWORD}"

# Check if user exists and create if not
psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname "${POSTGRES_DB}" <<-EOSQL
DO
\$\$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '${GRAFANA_USER}') THEN
        ALTER USER ${GRAFANA_USER} WITH PASSWORD '${GRAFANA_PASSWORD}';
        -- Optionally update privileges if they might have changed
        GRANT USAGE ON SCHEMA reporting TO ${GRAFANA_USER};
        GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO ${GRAFANA_USER};
        ALTER DEFAULT PRIVILEGES IN SCHEMA reporting GRANT SELECT ON TABLES TO ${GRAFANA_USER};
    ELSE
        CREATE USER ${GRAFANA_USER} WITH PASSWORD '${GRAFANA_PASSWORD}';
        GRANT USAGE ON SCHEMA reporting TO ${GRAFANA_USER};
        GRANT SELECT ON ALL TABLES IN SCHEMA reporting TO ${GRAFANA_USER};
        ALTER DEFAULT PRIVILEGES IN SCHEMA reporting GRANT SELECT ON TABLES TO ${GRAFANA_USER};
    END IF;
END
\$\$;
EOSQL

echo "User and permissions setup complete."

# Keep the process running
wait
