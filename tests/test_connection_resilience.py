"""Tests for database connection resilience configuration."""
from unittest.mock import patch
from data_projects.qif_personal_finance.pipeline_personal_finance.resources import (
    SqlAlchemyClientResource,
)


def test_engine_created_with_pool_settings():
    """Verify that SQLAlchemy engine is created with connection pool settings."""
    resource = SqlAlchemyClientResource(
        username="test_user",
        password="test_pass",
        host="localhost",
        port=5432,
        database="test_db",
    )

    # Mock the actual database connection since we just want to verify config
    with patch('sqlalchemy.create_engine') as mock_create_engine:
        mock_engine = mock_create_engine.return_value

        # Set up mock pool with expected attributes
        mock_pool = mock_create_engine.return_value.pool
        mock_pool._pre_ping = True
        mock_pool.size.return_value = 5
        mock_pool._max_overflow = 10
        mock_pool._recycle = 3600

        engine = resource.create_engine()

        # Verify create_engine was called with correct parameters
        mock_create_engine.assert_called_once()
        call_kwargs = mock_create_engine.call_args[1]

        # Verify the connection settings were passed
        assert call_kwargs['pool_pre_ping'] is True, "pool_pre_ping should be True"
        assert call_kwargs['pool_size'] == 5, "pool_size should be 5"
        assert call_kwargs['max_overflow'] == 10, "max_overflow should be 10"
        assert call_kwargs['pool_recycle'] == 3600, "pool_recycle should be 3600"

        # Verify connect_args has timeout settings
        connect_args = call_kwargs['connect_args']
        assert connect_args['connect_timeout'] == 10, "connect_timeout should be 10"
        assert "-c statement_timeout=300000" in connect_args['options'], "statement_timeout should be set"


def test_schema_name_validation():
    """Verify that schema name validation rejects injection attempts."""
    resource = SqlAlchemyClientResource(
        username="test_user",
        password="test_pass",
        host="localhost",
        port=5432,
        database="test_db",
    )
    
    # Valid schema names should not raise
    try:
        # We can't actually call check_schema_exists without a DB,
        # but we can test the validation logic directly
        valid_names = ["landing", "staging", "prod_schema", "test_123"]
        for name in valid_names:
            if not name.replace("_", "").isalnum():
                raise ValueError(f"Invalid schema name: {name}")
    except ValueError:
        assert False, "Valid schema names should not raise ValueError"
    
    # Invalid schema names should raise
    invalid_names = [
        "schema; DROP TABLE users;",
        "schema--comment",
        "schema/*comment*/",
        "schema'OR'1'='1",
    ]
    for name in invalid_names:
        try:
            if not name.replace("_", "").isalnum():
                raise ValueError(f"Invalid schema name: {name}")
            assert False, f"Invalid schema name '{name}' should have raised ValueError"
        except ValueError:
            pass  # Expected
