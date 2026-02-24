from __future__ import annotations

import os

from dagster import Failure, MetadataValue, Output, asset
from sqlalchemy import create_engine, text
from sqlalchemy.engine import URL


def _get_env(name: str) -> str:
    value = os.getenv(name, "").strip()
    if not value:
        raise Failure(f"Required environment variable is missing: {name}")
    return value


@asset(
    group_name="bootstrap_gates",
    description=(
        "Verifies required Postgres roles/extensions exist before ingestion starts."
    ),
)
def postgres_role_readiness_gate(context) -> Output[dict]:
    host = _get_env("DAGSTER_POSTGRES_HOST")
    port = int(_get_env("DAGSTER_POSTGRES_PORT"))
    database = _get_env("DAGSTER_POSTGRES_DB")
    admin_user = _get_env("POSTGRES_ADMIN_USER")
    admin_password = _get_env("POSTGRES_ADMIN_PASSWORD")
    dagster_user = _get_env("DAGSTER_POSTGRES_USER")
    dagster_password = _get_env("DAGSTER_POSTGRES_PASSWORD")
    grafana_user = _get_env("GRAFANA_USER")

    admin_url = URL.create(
        drivername="postgresql+psycopg2",
        username=admin_user,
        password=admin_password,
        host=host,
        port=port,
        database=database,
    )
    dagster_url = URL.create(
        drivername="postgresql+psycopg2",
        username=dagster_user,
        password=dagster_password,
        host=host,
        port=port,
        database=database,
    )

    roles = set()
    tablefunc_installed = False
    try:
        admin_engine = create_engine(admin_url)
        with admin_engine.connect() as conn:
            roles = {
                row[0]
                for row in conn.execute(
                    text(
                        "SELECT rolname FROM pg_roles "
                        "WHERE rolname IN (:dagster_user, :grafana_user)"
                    ),
                    {"dagster_user": dagster_user, "grafana_user": grafana_user},
                )
            }
            tablefunc_installed = (
                conn.execute(
                    text("SELECT 1 FROM pg_extension WHERE extname = 'tablefunc'")
                ).scalar()
                is not None
            )
    except Exception as exc:
        raise Failure(f"Failed admin readiness checks: {exc}") from exc

    missing_roles = []
    if dagster_user not in roles:
        missing_roles.append(dagster_user)
    if grafana_user not in roles:
        missing_roles.append(grafana_user)

    if missing_roles:
        raise Failure(
            "Required Postgres roles are missing.",
            metadata={
                "missing_roles": MetadataValue.json(missing_roles),
                "hint": MetadataValue.text(
                    "Check postgres init scripts and line endings, then recreate postgres volume."
                ),
            },
        )

    if not tablefunc_installed:
        raise Failure(
            "Postgres extension 'tablefunc' is not installed.",
            metadata={"database": MetadataValue.text(database)},
        )

    try:
        dagster_engine = create_engine(dagster_url)
        with dagster_engine.connect() as conn:
            conn.execute(text("SELECT 1"))
    except Exception as exc:
        raise Failure(
            f"Dagster service role login failed for user '{dagster_user}': {exc}"
        ) from exc

    context.log.info("Postgres role readiness checks passed.")
    return Output(
        {
            "dagster_user": dagster_user,
            "grafana_user": grafana_user,
            "tablefunc_installed": tablefunc_installed,
        }
    )
