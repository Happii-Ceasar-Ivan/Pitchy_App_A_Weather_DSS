"""Server-side configuration loaded from environment variables.

Values come from the process environment, then from ``backend/.env`` (git-ignored).
Never put secrets in code, in ``.env.example`` files, or in the Flutter client (NFR-SEC-001).
"""

from functools import lru_cache
from typing import Literal

from pydantic_settings import BaseSettings, SettingsConfigDict

Environment = Literal["development", "test", "production"]


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="PITCHY_",
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    env: Environment = "development"
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR"] = "INFO"

    @property
    def expose_api_docs(self) -> bool:
        """Interactive docs are disabled in production; the committed contract is the reference."""
        return self.env != "production"


@lru_cache
def get_settings() -> Settings:
    return Settings()
