"""Server-side configuration loaded from environment variables.

Values come from the process environment first, then from the repository-root ``.env``
(git-ignored). Never put secrets in code or in the Flutter client (NFR-SEC-001).
Secrets are ``SecretStr`` so they are masked in reprs and logs; empty values count as unset.
"""

from functools import lru_cache
from pathlib import Path
from typing import Literal

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict

Environment = Literal["development", "test", "production"]

ROOT_ENV_FILE = Path(__file__).resolve().parents[2] / ".env"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=ROOT_ENV_FILE,
        env_file_encoding="utf-8",
        env_ignore_empty=True,
        extra="ignore",
        populate_by_name=True,
    )

    env: Environment = Field(default="development", validation_alias="PITCHY_ENV")
    log_level: Literal["DEBUG", "INFO", "WARNING", "ERROR"] = Field(
        default="INFO", validation_alias="PITCHY_LOG_LEVEL"
    )

    supabase_url: str | None = Field(default=None, validation_alias="SUPABASE_URL")
    supabase_anon_key: SecretStr | None = Field(default=None, validation_alias="SUPABASE_ANON_KEY")
    supabase_service_role_key: SecretStr | None = Field(
        default=None, validation_alias="SUPABASE_SERVICE_ROLE_KEY"
    )
    supabase_db_url: SecretStr | None = Field(default=None, validation_alias="SUPABASE_DB_URL")

    ai_provider_primary: str | None = Field(default=None, validation_alias="AI_PROVIDER_PRIMARY")
    ai_provider_fallback: str | None = Field(default=None, validation_alias="AI_PROVIDER_FALLBACK")
    gemini_api_key: SecretStr | None = Field(default=None, validation_alias="GEMINI_API_KEY")
    nvidia_api_key: SecretStr | None = Field(default=None, validation_alias="NVIDIA_API_KEY")
    qwen_api_key: SecretStr | None = Field(default=None, validation_alias="QWEN_API_KEY")
    llama_api_key: SecretStr | None = Field(default=None, validation_alias="LLAMA_API_KEY")

    # Anonymous chatbot limits (P-06). Usage limits, not safety thresholds.
    chat_max_prompts: int = Field(default=10, ge=1, validation_alias="PITCHY_CHAT_MAX_PROMPTS")
    chat_window_minutes: int = Field(
        default=10, ge=1, validation_alias="PITCHY_CHAT_WINDOW_MINUTES"
    )
    chat_cooldown_minutes: int = Field(
        default=20, ge=1, validation_alias="PITCHY_CHAT_COOLDOWN_MINUTES"
    )
    session_token_secret: SecretStr | None = Field(
        default=None, validation_alias="PITCHY_SESSION_TOKEN_SECRET"
    )

    @property
    def expose_api_docs(self) -> bool:
        """Interactive docs are disabled in production; the committed contract is the reference."""
        return self.env != "production"


@lru_cache
def get_settings() -> Settings:
    return Settings()
