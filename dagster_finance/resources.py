from dagster import resource
from typing import Dict
import os
from dagster import ConfigurableResource, InitResourceContext
from sqlalchemy import create_engine
from sqlalchemy.engine import URL
from contextlib import contextmanager
from pydantic import PrivateAttr


class DBConnection:
    def __init__(self, url):
        self.engine = create_engine(url)

    def query(self, body: str):
        with self.engine.connect() as connection:
            result = connection.execute(body)
            return result.fetchall()

@contextmanager
def get_database_connection():
    connection_url = os.getenv('POSTGRES_CONN_STR')
    if not connection_url:
        raise Exception("POSTGRES_CONN_STR environment variable must be set")
    
    db_connection = DBConnection(connection_url)
    try:
        yield db_connection
    finally:
        db_connection.engine.dispose()

@resource
class pgConnection(ConfigurableResource):

    _db_connection: DBConnection = PrivateAttr(default=None)

    def __init__(self, context: InitResourceContext):
        self._db_connection = None 
        super().__init__(context) 

    @contextmanager
    def yield_for_execution(self):
        # keep connection open for the duration of the execution
        with get_database_connection() as conn:
            self._db_connection = conn
            yield self
            self._db_connection = None 

    def query(self, body: str):
        if self._db_connection is None:
            raise Exception("Database connection not established")
        return self._db_connection.query(body)
