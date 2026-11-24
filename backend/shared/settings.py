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
        env_file_encoding="utf-8-sig",  # tolerates editors that save a BOM
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
    app_db_url: SecretStr | None = Field(default=None, validation_alias="PITCHY_APP_DB_URL")

    # AI providers (DEC-10): Gemini, then Groq, then OpenRouter (free models). The order, model
    # names and timeouts are code constants. Keys go in request headers, never in URLs or logs.
    gemini_api_key: SecretStr | None = Field(default=None, validation_alias="GEMINI_API_KEY")
    groq_api_key: SecretStr | None = Field(default=None, validation_alias="GROQ_API_KEY")
    openrouter_api_key: SecretStr | None = Field(
        default=None, validation_alias="OPENROUTER_API_KEY"
    )

    # Vaisala Xweather (lightning, DEC-06). Sent as query parameters: never log request URLs.
    xweather_client_id: SecretStr | None = Field(
        default=None, validation_alias="XWEATHER_CLIENT_ID"
    )
    xweather_client_secret: SecretStr | None = Field(
        default=None, validation_alias="XWEATHER_CLIENT_SECRET"
    )
    lightning_radius_km: float = Field(
        default=40, gt=0, le=40, validation_alias="PITCHY_LIGHTNING_RADIUS_KM"
    )  # Xweather's maximum for lightning/flash
    lightning_check_minutes: float = Field(
        default=5, ge=1, validation_alias="PITCHY_LIGHTNING_CHECK_MINUTES"
    )  # one shared check per venue at most this often (data covers the past 5 minutes)
    lightning_window_before_kickoff_minutes: float = Field(
        default=120, ge=0, validation_alias="PITCHY_LIGHTNING_WINDOW_BEFORE_MINUTES"
    )  # live checks only from this long before kickoff until the coverage window ends

    # Development-only demo routes (/api/v1/dev/...). Need PITCHY_ENV=development AND this flag,
    # and still answer only requests from this computer.
    enable_dev_routes: bool = Field(default=False, validation_alias="PITCHY_ENABLE_DEV_ROUTES")

    # Sent to weather sources. Generic by default; set it to identify the project if wanted.
    http_user_agent: str = Field(
        default="weather-dss-client/0.1", validation_alias="PITCHY_HTTP_USER_AGENT"
    )

    # Data-quality rules (DEC-04, team decision 2026-11-22). Not safety thresholds.
    match_coverage_hours: float = Field(
        default=2, gt=0, validation_alias="PITCHY_MATCH_COVERAGE_HOURS"
    )  # forecasts must cover kickoff .. kickoff + this
    fresh_open_meteo_hours: float = Field(
        default=7, gt=0, validation_alias="PITCHY_FRESH_OPEN_METEO_HOURS"
    )  # by retrieval time (Open-Meteo does not report its model run)
    fresh_pagasa_atmo_hours: float = Field(
        default=12, gt=0, validation_alias="PITCHY_FRESH_PAGASA_ATMO_HOURS"
    )  # by model run (init)
    fresh_pagasa_ecmwf_hours: float = Field(
        default=24, gt=0, validation_alias="PITCHY_FRESH_PAGASA_ECMWF_HOURS"
    )  # by model run (init)
    fresh_alerts_minutes: float = Field(
        default=60, gt=0, validation_alias="PITCHY_FRESH_ALERTS_MINUTES"
    )  # by last check; also the most often alerts are fetched (DEC-02)

    retry_after_failure_minutes: float = Field(
        default=15, gt=0, validation_alias="PITCHY_RETRY_AFTER_FAILURE_MINUTES"
    )  # manual Ingest waits this long after a failed attempt (DEC-04 option C)

    # Retention (DEC-11, team decision 2026-11-22). Run by the ingest job after each run.
    retention_forecast_days: float = Field(
        default=14, ge=1, validation_alias="PITCHY_RETENTION_FORECAST_DAYS"
    )  # forecast values and source fetches
    retention_job_days: float = Field(
        default=30, ge=1, validation_alias="PITCHY_RETENTION_JOB_DAYS"
    )  # finished ingestion jobs, alert checks and their alerts

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
    )  # signs and hashes anonymous session tokens (HMAC-SHA256)
    # Values confirmed by the user 2026-11-24 (B5 plan section 7).
    chat_sessions_per_ip_per_hour: int = Field(
        default=30, ge=1, validation_alias="PITCHY_CHAT_SESSIONS_PER_IP_PER_HOUR"
    )  # new sessions per client IP (in memory, hashed IP, never stored)
    chat_daily_ai_cap: int = Field(
        default=500, ge=0, validation_alias="PITCHY_CHAT_DAILY_AI_CAP"
    )  # questions per day (from midnight Asia/Manila) that may call an AI provider, all users
    forwarded_hops: int = Field(
        default=0, ge=0, le=5, validation_alias="PITCHY_FORWARDED_HOPS"
    )  # trusted proxies in front of the app: client IP = X-Forwarded-For entry this far from the
    # right (0 = the direct peer; Azure Container Apps = 1). Never the client-supplied left side.
    retention_conversation_days: float = Field(
        default=30, ge=1, validation_alias="PITCHY_RETENTION_CONVERSATION_DAYS"
    )  # conversation_events rows and anonymous sessions idle this long

    @property
    def expose_api_docs(self) -> bool:
        """Interactive docs are disabled in production; the committed contract is the reference."""
        return self.env != "production"


@lru_cache
def get_settings() -> Settings:
    return Settings()
