# pipeline_personal_finance/resources.py

import sqlalchemy
from dagster import ConfigurableResource, EnvVar


drivername = "postgresql+psycopg2"

class SqlAlchemyClientResource(ConfigurableResource):
    drivername: str = "postgresql+psycopg2"
    username: str = EnvVar("DAGSTER_POSTGRES_USER")
    password: str = EnvVar("DAGSTER_POSTGRES_PASSWORD")
    host: str = EnvVar("DAGSTER_POSTGRES_HOST")
    port: int = EnvVar("DAGSTER_POSTGRES_PORT")
    database: str = EnvVar("DAGSTER_POSTGRES_DB")


    def create_engine(self):
        connection_string = sqlalchemy.URL.create(                
                drivername=self.drivername,
                username=self.username,
                password=self.password,
                host=self.host,
                port=int(self.port),
                database=self.database
            )
        
        return sqlalchemy.create_engine(connection_string)

    def get_connection(self):
        return self.create_engine().connect()