from dagster import EnvVar, resource
from typing import Dict, Any
import os
from dagster import ConfigurableResource, InitResourceContext
from sqlalchemy import create_engine
from sqlalchemy.engine import URL
from contextlib import contextmanager
from pydantic import PrivateAttr


class DBConnection:
    def __init__(self, url: str):
        self.engine = create_engine(url)

    def query(self, body: str):
        with self.engine.connect() as connection:
            result = connection.execute(body)
            return result.fetchall()

@contextmanager
def get_database_connection(connection_url: str):
    if not connection_url:
        raise ValueError("Connection URL must be provided")
    
    db_connection = DBConnection(connection_url)
    try:
        yield db_connection
    finally:
        db_connection.engine.dispose()

class pgConnection: #(ConfigurableResource):
    def __init__(self, connection_url: str):
        if not connection_url:
            raise ValueError("A valid connection URL must be provided")
        self.connection_url = connection_url
        self._db_connection = None
        
    @contextmanager
    def yield_for_execution(self):
        # keep connection open for the duration of the execution
        with get_database_connection(self.connection_url) as conn:
            self._db_connection = conn
            yield self
            self._db_connection = None 

    def query(self, body: str):
        if self._db_connection is None:
            raise Exception("Database connection not established")
        return self._db_connection.query(body)

if __name__ == "__main__":
    # Example usage of the database connection and query
    postgres_conn_str = os.getenv("POSTGRES_CONN_STR")
    print(f"Postgres Connection String: {postgres_conn_str}")
    pg_conn = pgConnection(postgres_conn_str)  # Assuming no context is needed for demonstration.
    with pg_conn.yield_for_execution():
        # Example query - adjust the SQL to fit your actual database schema and purpose
        results = pg_conn.query("SELECT * FROM pg_catalog.pg_tables WHERE schemaname='public' LIMIT 10;")
        print(results)