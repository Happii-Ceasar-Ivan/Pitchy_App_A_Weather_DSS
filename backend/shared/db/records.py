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
    submunicipality_psgc_code: str | None = None

    @property
    def alert_codes(self) -> set[str]:
        """Every PSGC code an official alert may use for this venue (FR-SAF-007)."""
        codes = (self.submunicipality_psgc_code, self.psgc_code, self.province_psgc_code)
        return {c for c in codes if c}


@dataclass(frozen=True)
class MatchContextRecord:
    id: UUID
    kickoff_at: datetime
    location_id: UUID
    venue_name: str | None
    pitch_surface: str | None
    created_at: datetime
    updated_at: datetime
    age_group: str = "senior"  # 'senior' | 'youth_u20' (B4)


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


@dataclass(frozen=True)
class FetchCoverage:
    """One successful fetch and the validity windows of its usable values near a match."""

    fetch_id: UUID
    retrieved_at: datetime
    source_issued_at: datetime | None
    windows: tuple[tuple[datetime, datetime], ...]  # (valid_from, valid_until), sorted


@dataclass(frozen=True)
class FetchAttempt:
    """The latest call to a source for a location, successful or not."""

    id: UUID
    status: str  # 'succeeded' | 'failed'
    requested_at: datetime
    error_code: str | None
    error_summary: str | None


@dataclass(frozen=True)
class FetchFailureRecord:
    source_id: str
    error_code: str | None
    error_summary: str | None


@dataclass(frozen=True)
class AlertCheckRecord:
    id: UUID
    ingestion_job_id: UUID | None
    checked_at: datetime
    status: str
    error_code: str | None
    error_summary: str | None
    active_cyclones: int | None
    alert_count: int | None
    created_at: datetime


@dataclass(frozen=True)
class StoredAlertRecord:
    id: UUID
    check_id: UUID
    identifier: str
    issuer: str
    event: str
    subtype: str
    headline: str
    message: str
    issued_at: datetime | None
    valid_until: datetime | None
    areas: list[dict]
    matched_venues: list[str]
    created_at: datetime


@dataclass(frozen=True)
class LightningCheckRecord:
    id: UUID
    location_id: UUID
    ingestion_job_id: UUID | None
    checked_at: datetime
    status: str
    error_code: str | None
    error_summary: str | None
    radius_km: float | None
    flash_count: int | None
    nearest_km: float | None
    latest_flash_at: datetime | None
    flashes: list[dict]
    raw_payload: str | None
    raw_payload_sha256: str | None
    created_at: datetime
