from dagster import resource
from typing import Dict
import os

@resource
def postgres_db_resource(init_context) -> str:
    conn_str = os.getenv('POSTGRES_CONN_STR')
    if not conn_str:
        raise Exception("POSTGRES_CONN_STR environment variable must be set")
    return conn_str