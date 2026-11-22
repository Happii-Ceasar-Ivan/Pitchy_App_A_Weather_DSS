"""Row types returned by the repositories. Field names match the table columns exactly."""

from dataclasses import dataclass
from datetime import datetime
from uuid import UUID


@dataclass(frozen=True)
class WeatherSource:
    id: str
    name: str
    access_method: str
    enabled: bool
    config_ref: str | None
    created_at: datetime
    updated_at: datetime


@dataclass(frozen=True)
class Location:
    id: UUID
    name: str | None
    latitude: float
    longitude: float
    scope_key: str
    created_at: datetime
    updated_at: datetime
    psgc_code: str | None = None
    province_psgc_code: str | None = None


@dataclass(frozen=True)
class MatchContextRecord:
    id: UUID
    kickoff_at: datetime
    location_id: UUID
    venue_name: str | None
    pitch_surface: str | None
    created_at: datetime
    updated_at: datetime


@dataclass(frozen=True)
class IngestionJobRecord:
    id: UUID
    scope_key: str
    source_id: str
    location_id: UUID
    state: str
    requested_at: datetime
    started_at: datetime | None
    finished_at: datetime | None
    lease_expires_at: datetime
    failure_code: str | None
    failure_message: str | None
    created_at: datetime
    updated_at: datetime


@dataclass(frozen=True)
class LockResult:
    """Outcome of trying to take the ingestion lock for a scope."""

    job: IngestionJobRecord
    acquired: bool  # False: another request already holds it; poll ``job`` instead.


@dataclass(frozen=True)
class NewForecastValue:
    parameter: str
    value: float | None
    unit: str | None
    value_state: str  # 'ok' | 'missing' | 'invalid'
    forecast_valid_from: datetime | None
    forecast_valid_until: datetime | None
    expires_at: datetime | None


@dataclass(frozen=True)
class ForecastValueRecord:
    id: int
    fetch_id: UUID
    source_id: str
    location_id: UUID
    parameter: str
    value: float | None
    unit: str | None
    value_state: str
    retrieved_at: datetime
    forecast_valid_from: datetime | None
    forecast_valid_until: datetime | None
    expires_at: datetime | None
    created_at: datetime


@dataclass(frozen=True)
class AnonymousSessionRecord:
    id: UUID
    token_hash: bytes
    counted_prompt_times: list[datetime]
    cooldown_until: datetime | None
    last_request_at: datetime | None
    created_at: datetime
    updated_at: datetime
