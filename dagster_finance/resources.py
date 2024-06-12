from dagster import EnvVar, resource
from typing import Dict, Any
import os
from dagster import ConfigurableResource, InitResourceContext
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL
from contextlib import contextmanager
from pydantic import PrivateAttr


class DBConnection:
    def __init__(self, engine):
        self.engine = engine

    def query(self, body: text):
        with self.engine.connect() as connection:
            result = connection.execute(body)
            return result.fetchall()

@contextmanager
def get_database_connection(connection_url: str):
    engine = create_engine(connection_url)    
    db_connection = DBConnection(engine)
    try:
        yield db_connection
    finally:
        engine.dispose()

class pgConnection(ConfigurableResource):
    connection_string= str

    _db_connection: DBConnection = PrivateAttr()
   
    @contextmanager
    def yield_for_execution(self, context: InitResourceContext):
        # keep connection open for the duration of the execution
        with get_database_connection(self.connection_string) as conn:
            self._db_connection = conn

            yield self

    def query(self, body: str):
        return self._db_connection.query(text(body))

if __name__ == "__main__":
    # Example usage of the database connection and query
    postgres_conn_str = os.getenv("POSTGRES_CONN_STR")
    print(f"Postgres Connection String: {postgres_conn_str}")
    pg_conn = pgConnection(postgres_conn_str)  # Assuming no context is needed for demonstration.
    with pg_conn.yield_for_execution():
        # Example query - adjust the SQL to fit your actual database schema and purpose
        results = pg_conn.query('SELECT date, amount, memo, line_number, splits, composite_key, ingestion_date FROM landing."Adelaide_Homeloan_Transactions";')
        print(results)