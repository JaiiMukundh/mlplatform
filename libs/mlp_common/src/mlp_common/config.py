"""Environment-backed settings shared by every Python service."""

from __future__ import annotations

from functools import lru_cache
from typing import TypeVar

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class ServiceSettings(BaseSettings):
    """Minimum configuration contract implemented by every service."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
        case_sensitive=False,
    )

    service_name: str = "mlplatform"
    log_level: str = "INFO"

    @field_validator("log_level")
    @classmethod
    def validate_log_level(cls, value: str) -> str:
        """Normalize and validate Python logging levels."""
        normalized = value.upper()
        if normalized not in {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}:
            msg = f"unsupported log level: {value}"
            raise ValueError(msg)
        return normalized


SettingsT = TypeVar("SettingsT", bound=ServiceSettings)


@lru_cache
def load_settings(settings_type: type[SettingsT] = ServiceSettings) -> SettingsT:
    """Load and cache an environment-backed settings instance."""
    return settings_type()
