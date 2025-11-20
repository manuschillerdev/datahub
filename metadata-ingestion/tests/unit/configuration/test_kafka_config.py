import ssl
from typing import Any, Dict
from unittest.mock import MagicMock, patch

from datahub.configuration.kafka import process_schema_registry_config


class TestProcessSchemaRegistryConfig:
    """Test suite for process_schema_registry_config function."""

    @patch("datahub.configuration.kafka.ssl.create_default_context")
    def test_process_schema_registry_config_with_ssl_ca_location(
        self, mock_create_context: MagicMock
    ) -> None:
        """Test that ssl.ca.location string paths are converted to SSL contexts."""
        mock_ssl_context = MagicMock(spec=ssl.SSLContext)
        mock_create_context.return_value = mock_ssl_context

        config: Dict[str, Any] = {
            "url": "https://schema-registry:8081",
            "ssl.ca.location": "/path/to/ca-cert.pem",
            "basic.auth.user.info": "user:pass",
        }

        result = process_schema_registry_config(config)

        mock_create_context.assert_called_once_with(cafile="/path/to/ca-cert.pem")
        assert result["ssl.ca.location"] is mock_ssl_context
        assert result["url"] == "https://schema-registry:8081"
        assert result["basic.auth.user.info"] == "user:pass"

    def test_process_schema_registry_config_without_ssl(self) -> None:
        """Test that configs without SSL pass through unchanged."""
        config: Dict[str, Any] = {
            "url": "http://schema-registry:8081",
            "basic.auth.user.info": "user:pass",
        }

        result = process_schema_registry_config(config)

        assert result == config
        assert "ssl.ca.location" not in result

    def test_process_schema_registry_config_with_existing_context(self) -> None:
        """Test that existing SSL context objects are not re-processed."""
        existing_context = ssl.create_default_context()
        config: Dict[str, Any] = {
            "url": "https://schema-registry:8081",
            "ssl.ca.location": existing_context,
        }

        result = process_schema_registry_config(config)

        assert result["ssl.ca.location"] is existing_context

    @patch("datahub.configuration.kafka.ssl.create_default_context")
    def test_process_schema_registry_config_preserves_other_settings(
        self, mock_create_context: MagicMock
    ) -> None:
        """Test that all other config keys are preserved during processing."""
        mock_ssl_context = MagicMock(spec=ssl.SSLContext)
        mock_create_context.return_value = mock_ssl_context

        config: Dict[str, Any] = {
            "url": "https://schema-registry:8081",
            "ssl.ca.location": "/path/to/ca-cert.pem",
            "basic.auth.user.info": "user:pass",
            "basic.auth.credentials.source": "USER_INFO",
            "ssl.certificate.location": "/path/to/cert.pem",
            "ssl.key.location": "/path/to/key.pem",
        }

        result = process_schema_registry_config(config)

        assert result["ssl.ca.location"] is mock_ssl_context
        assert result["url"] == config["url"]
        assert result["basic.auth.user.info"] == config["basic.auth.user.info"]
        assert (
            result["basic.auth.credentials.source"]
            == config["basic.auth.credentials.source"]
        )
        assert result["ssl.certificate.location"] == config["ssl.certificate.location"]
        assert result["ssl.key.location"] == config["ssl.key.location"]

    @patch("datahub.configuration.kafka.ssl.create_default_context")
    def test_process_schema_registry_config_does_not_modify_original(
        self, mock_create_context: MagicMock
    ) -> None:
        """Test that the original config dict is not modified."""
        mock_ssl_context = MagicMock(spec=ssl.SSLContext)
        mock_create_context.return_value = mock_ssl_context

        original_config: Dict[str, Any] = {
            "url": "https://schema-registry:8081",
            "ssl.ca.location": "/path/to/ca-cert.pem",
        }
        original_ssl_value = original_config["ssl.ca.location"]

        process_schema_registry_config(original_config)

        assert original_config["ssl.ca.location"] == original_ssl_value
        assert isinstance(original_config["ssl.ca.location"], str)

    def test_process_schema_registry_config_empty_config(self) -> None:
        """Test that empty configs are handled correctly."""
        config: Dict[str, Any] = {}

        result = process_schema_registry_config(config)

        assert result == {}
