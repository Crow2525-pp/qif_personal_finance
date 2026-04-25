# data_projects/qif_personal_finance/pipeline_personal_finance/resources.py

import sqlalchemy
from dagster import ConfigurableResource, EnvVar


drivername = "postgresql+psycopg2"


def _resolve_env(value, *, default=None):
    if hasattr(value, "get_value"):
        return value.get_value(default)
    return value


class SqlAlchemyClientResource(ConfigurableResource):
    drivername: str = "postgresql+psycopg2"
    username: str = EnvVar("DAGSTER_POSTGRES_USER")
    password: str = EnvVar("DAGSTER_POSTGRES_PASSWORD")
    host: str = EnvVar("DAGSTER_POSTGRES_HOST")
    port: int = EnvVar.int("DAGSTER_POSTGRES_PORT")
    database: str = EnvVar("DAGSTER_POSTGRES_DB")

    def create_engine(self):
        connection_string = sqlalchemy.URL.create(
            drivername=self.drivername,
            username=_resolve_env(self.username),
            password=_resolve_env(self.password),
            host=_resolve_env(self.host),
            port=int(_resolve_env(self.port, default="5432")),
            database=_resolve_env(self.database),
        )

        return sqlalchemy.create_engine(connection_string)

    def get_connection(self):
        """Returns a connection that should be used in a context manager.

        The engine will be disposed when the connection is closed.
        """
        engine = self.create_engine()
        conn = engine.connect()
        # Dispose engine when connection closes
        original_close = conn.close

        def close_with_dispose():
            original_close()
            engine.dispose()

        conn.close = close_with_dispose
        return conn

    def check_schema_exists(self, schema: str = "landing"):
        """Ensure the schema exists. Validates schema name to prevent injection."""
        # Validate schema name to prevent injection
        if not schema.replace("_", "").isalnum():
            raise ValueError(f"Invalid schema name: {schema}")

        # CREATE SCHEMA IF NOT EXISTS doesn't support parameterization, but we validated above
        create_schema_sql = f"CREATE SCHEMA IF NOT EXISTS {schema};"
        verify_schema_sql = "SELECT schema_name FROM information_schema.schemata WHERE schema_name = :schema"
        check_db_sql = "SELECT current_database();"

        with self.get_connection() as conn:
            # Check the current database name
            result = conn.execute(sqlalchemy.text(check_db_sql)).fetchone()
            current_db = result[0] if result else "Unknown"

            conn.execute(sqlalchemy.text(create_schema_sql))
            conn.commit()  # Commit the schema creation

            result = conn.execute(sqlalchemy.text(verify_schema_sql), {"schema": schema}).fetchone()
            if not result:
                raise RuntimeError(
                    f"Failed to create or verify the existence of schema '{schema}'."
                )
