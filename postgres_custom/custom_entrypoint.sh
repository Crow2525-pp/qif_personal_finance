#!/bin/bash
set -e

# Start the original entrypoint script with PostgreSQL in the background
docker-entrypoint.sh postgres &

# Wait for PostgreSQL to start
until pg_isready -U ${POSTGRES_USER} -d ${POSTGRES_DB}; do
  echo "Waiting for PostgreSQL to start..."
  sleep 1
done

# Run custom SQL commands
psql -v ON_ERROR_STOP=1 --username "${POSTGRES_USER}" --dbname "${POSTGRES_DB}" <<-EOSQL
    CREATE USER grafanareader WITH PASSWORD 'test';
    GRANT USAGE ON SCHEMA public TO grafanareader;
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafanareader;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO grafanareader;
EOSQL

# Keep PostgreSQL running in the foreground
wait
