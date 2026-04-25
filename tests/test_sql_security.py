"""Tests for SQL injection prevention and resource management."""

import pytest
from unittest.mock import MagicMock, patch

from data_projects.qif_personal_finance.pipeline_personal_finance.resources import (
    SqlAlchemyClientResource,
)


def test_check_schema_exists_validates_schema_name():
    """Schema name validation prevents SQL injection."""
    resource = SqlAlchemyClientResource(
        username="test",
        password="test",
        host="localhost",
        port=5432,
        database="test",
    )

    # Invalid schema names with SQL injection attempts should raise ValueError
    # before any database operations occur
    with pytest.raises(ValueError, match="Invalid schema name"):
        resource.check_schema_exists("schema'; DROP TABLE users; --")

    with pytest.raises(ValueError, match="Invalid schema name"):
        resource.check_schema_exists("schema OR 1=1")

    with pytest.raises(ValueError, match="Invalid schema name"):
        resource.check_schema_exists("schema--comment")

    with pytest.raises(ValueError, match="Invalid schema name"):
        resource.check_schema_exists("schema; DELETE FROM data")

    # Spaces and special chars should also be rejected
    with pytest.raises(ValueError, match="Invalid schema name"):
        resource.check_schema_exists("schema name")

    with pytest.raises(ValueError, match="Invalid schema name"):
        resource.check_schema_exists("schema.table")


def test_get_connection_disposes_engine_on_close():
    """Engine disposal prevents connection pool exhaustion."""
    resource = SqlAlchemyClientResource(
        username="test",
        password="test",
        host="localhost",
        port=5432,
        database="test",
    )

    with patch("data_projects.qif_personal_finance.pipeline_personal_finance.resources.sqlalchemy.create_engine") as mock_create_engine:
        mock_engine = MagicMock()
        mock_conn = MagicMock()
        mock_create_engine.return_value = mock_engine
        mock_engine.connect.return_value = mock_conn

        conn = resource.get_connection()
        conn.close()

        # Verify engine.dispose() was called
        mock_engine.dispose.assert_called_once()
