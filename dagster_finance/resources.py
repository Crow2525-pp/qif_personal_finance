from dagster import EnvVar, build_resources, resource
from typing import Dict, Any, Union
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
    connection_string: str # BUG: Should be able to use EnvVar

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

    # Manually create an instance of pgConnection with the connection string
    pg_conn = pgConnection(connection_string=postgres_conn_str)

    with pg_conn.yield_for_execution(None):
        # Example query - adjust the SQL to fit your actual database schema and purpose
        query = """ 
        SELECT 
            table_schema, 
            table_name, 
            table_type
        FROM 
            information_schema.tables
        WHERE 
            table_type = 'BASE TABLE'
            AND table_schema NOT IN ('information_schema', 'pg_catalog')
        ORDER BY 
            table_schema, 
            table_name;
        """
        print(query)
        results = pg_conn.query(query)
        print(results)

        query2 = """
        SELECT 
            date, 
            amount, 
            memo,
            line_number,
            splits,
            primary_key,
            ingestion_date 
        FROM raw."Adelaide_Homeloan_Transactions;
        """

        # results = pg_conn.query(query2)
        print(results)