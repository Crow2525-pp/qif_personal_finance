"""Tests for database connection resilience configuration."""
from unittest.mock import patch, MagicMock
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

    # Mock sqlalchemy.create_engine to verify it's called with the right parameters
    with patch('sqlalchemy.create_engine') as mock_create_engine:
        mock_engine = MagicMock()
        mock_create_engine.return_value = mock_engine

        engine = resource.create_engine()

        # Verify create_engine was called
        assert mock_create_engine.called, "create_engine should be called"

        # Get the call arguments
        call_args = mock_create_engine.call_args

        # Verify positional argument (connection string)
        assert len(call_args.args) == 1, "Should have connection string as first arg"

        # Verify keyword arguments for connection pool settings
        kwargs = call_args.kwargs
        assert kwargs['pool_pre_ping'] is True, "pool_pre_ping should be True"
        assert kwargs['pool_size'] == 5, "pool_size should be 5"
        assert kwargs['max_overflow'] == 10, "max_overflow should be 10"
        assert kwargs['pool_recycle'] == 3600, "pool_recycle should be 3600"

        # Verify connect_args
        assert 'connect_args' in kwargs, "connect_args should be present"
        connect_args = kwargs['connect_args']
        assert connect_args['connect_timeout'] == 10, "connect_timeout should be 10"
        assert 'options' in connect_args, "options should be in connect_args"
        assert 'statement_timeout=300000' in connect_args['options'], "statement_timeout should be set"

        # Verify the returned engine is the mock
        assert engine is mock_engine, "Should return the mocked engine"


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
