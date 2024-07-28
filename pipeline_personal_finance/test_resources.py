# tests/test_resources.py

import os
import pytest
from unittest.mock import patch, MagicMock
from pipeline_personal_finance.resources import SqlAlchemyClientResource

@pytest.fixture
def mock_env_vars(monkeypatch):
    monkeypatch.setenv("DAGSTER_POSTGRES_USER", "test_user")
    monkeypatch.setenv("DAGSTER_POSTGRES_PASSWORD", "test_password")
    monkeypatch.setenv("DAGSTER_POSTGRES_HOST", "localhost")
    monkeypatch.setenv("DAGSTER_POSTGRES_PORT", "5432")
    monkeypatch.setenv("DAGSTER_POSTGRES_DB", "test_db")

def test_create_engine(mock_env_vars):
    resource = SqlAlchemyClientResource()
    
    with patch("sqlalchemy.create_engine") as mock_create_engine:
        mock_engine = MagicMock()
        mock_create_engine.return_value = mock_engine

        engine = resource.create_engine()

        mock_create_engine.assert_called_once()
        assert engine == mock_engine

def test_get_connection(mock_env_vars):
    resource = SqlAlchemyClientResource()

    with patch.object(resource, 'create_engine') as mock_create_engine:
        mock_engine = MagicMock()
        mock_connection = MagicMock()
        mock_engine.connect.return_value = mock_connection
        mock_create_engine.return_value = mock_engine

        connection = resource.get_connection()

        mock_create_engine.assert_called_once()
        mock_engine.connect.assert_called_once()
        assert connection == mock_connection
