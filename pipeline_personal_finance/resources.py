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
    
    def check_schema_exists(self, schema: str):
        # Ensure the landing schema exists
        schema = "landing"
        create_schema_sql = f"CREATE SCHEMA IF NOT EXISTS {schema};"
        verify_schema_sql = f"SELECT schema_name FROM information_schema.schemata WHERE schema_name = '{schema}';"
        check_db_sql = "SELECT current_database();"

        with self.get_connection() as conn:
            try:
                # Check the current database name
                result = conn.execute(sqlalchemy.text(check_db_sql)).fetchone()
                current_db = result[0] if result else "Unknown"

                conn.execute(sqlalchemy.text(create_schema_sql))
                conn.commit()  # Commit the schema creation

                result = conn.execute(sqlalchemy.text(verify_schema_sql)).fetchone()
                if not result:
                    raise RuntimeError(
                        f"Failed to create or verify the existence of schema '{schema}'."
                    )
            except Exception as e:
                raise
