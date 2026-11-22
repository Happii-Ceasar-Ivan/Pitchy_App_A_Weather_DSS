"""Weather status, provenance and ingestion contract (FR-WTH-002..006, NFR-USE-001).

Data-state vocabulary decided in P-05 (follows SRS NFR-USE-001). "Ingest" is an action
(``ingestion_needed``), not a state.
"""

from enum import StrEnum
from uuid import UUID

from pydantic import AwareDatetime, Field

from api.schemas.common import ContractModel, Limitation


class WeatherDataState(StrEnum):
    CURRENT = "current"
    STALE = "stale"
    MISSING = "missing"
    UPDATING = "updating"
    UNAVAILABLE = "unavailable"


class Provenance(ContractModel):
    """Where and when a value came from (FR-WTH-005). Fields are null when a source omits them."""

    source_id: str
    source_name: str
    retrieved_at: AwareDatetime | None
    source_issued_at: AwareDatetime | None = Field(
        default=None, description="Model run time, when the source reports it (PAGASA `init`)."
    )
    forecast_valid_from: AwareDatetime | None
    forecast_valid_until: AwareDatetime | None
    expires_at: AwareDatetime | None


class SourceStatus(ContractModel):
    source_id: str
    source_name: str
    state: WeatherDataState
    covers_match_time: bool = Field(
        description="True when stored forecasts cover the whole coverage window without a gap."
    )
    current_until: AwareDatetime | None = Field(
        default=None,
        description="When the data used stops being current (DEC-04). Null when nothing is used.",
    )
    provenance: Provenance | None = Field(
        description="The fetch whose data is used; its valid times are those covering the match."
        " Null when nothing covers the match."
    )
    limitations: list[Limitation] = Field(default_factory=list)


class CoverageWindow(ContractModel):
    """Forecasts must cover this window to count (DEC-04: kickoff to kickoff + 2 h)."""

    start: AwareDatetime
    end: AwareDatetime


class AlertsStatus(ContractModel):
    """Freshness of the nationwide PAGASA alerts check (DEC-04: current while checked < 1 h
    ago). Alerts refresh on their own (schedule, and on open via GET .../alerts); they never
    make ``ingestion_needed`` true."""

    state: WeatherDataState
    last_checked_at: AwareDatetime | None = Field(description="Last successful check.")
    current_until: AwareDatetime | None
    last_error_code: str | None = Field(
        default=None, description="Set when the latest attempt failed."
    )


class WeatherStatus(ContractModel):
    match_context_id: UUID
    venue: str = Field(description="The match's venue scope key.")
    checked_at: AwareDatetime
    coverage: CoverageWindow
    sources: list[SourceStatus]
    ingestion_needed: bool = Field(
        description="Any enabled source stale, missing or unavailable and not updating (DEC-04)."
        " The client shows Ingest only when this is true."
    )
    active_job_ids: list[UUID] = Field(
        description="Ingestion jobs running for this venue now; poll GET /ingestions/{id}."
    )
    next_ingestion_at: AwareDatetime | None = Field(
        default=None,
        description="Set when a source needing data must wait: PAGASA's 4-hour gap (FR-WTH-008)"
        " or the cooldown after a failed attempt (DEC-04). Ingest before then cannot refresh it.",
    )
    alerts: AlertsStatus


class IngestionJobState(StrEnum):
    QUEUED = "queued"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    EXPIRED = "expired"


class IngestionFailure(ContractModel):
    source_id: str | None = Field(default=None, description="Null for a job-level failure.")
    code: str
    message: str = Field(description="Safe summary. Never contains secrets or raw responses.")


class IngestionJob(ContractModel):
    """One source group at one venue (e.g. PAGASA ATMO + ECMWF). Holds that scope's lock."""

    id: UUID
    state: IngestionJobState
    venue: str = Field(description="Venue scope key.")
    source_ids: list[str]
    created_at: AwareDatetime
    started_at: AwareDatetime | None
    finished_at: AwareDatetime | None
    failures: list[IngestionFailure] = Field(default_factory=list)
    reused_existing_job: bool = Field(
        description="True when another request or the schedule already started this job"
        " (FR-WTH-004). Always false on GET /ingestions/{id}."
    )


class IngestionRequestResult(ContractModel):
    """Answer to a manual Ingest: one job per source group that needed data."""

    match_context_id: UUID
    jobs: list[IngestionJob] = Field(min_length=1)


# --- Consolidated weather (P-09) -----------------------------------------------------------


class SourceValueOut(ContractModel):
    source_id: str
    value: float
    state: WeatherDataState = Field(description="`current` or `stale`.")
    note: str | None = Field(default=None, examples=["Height not stated."])


class ValueRangeOut(ContractModel):
    """Spread across current, comparable sources. Not an agreement label (no tolerances yet)."""

    min: float
    max: float
    count: int = Field(ge=2)
    source_ids: list[str]


class ConsolidatedSlot(ContractModel):
    valid_from: AwareDatetime
    valid_until: AwareDatetime
    value: float | None = Field(description="Null when no source has a value for this hour.")
    source_id: str | None = Field(description="Source of the chosen value.")
    state: WeatherDataState | None = Field(
        description="`current`, or `stale` when no current source had a value (show as stale)."
    )
    fallback_label: str | None = Field(
        description="Set when a lower-priority source was used, e.g. "
        "'Rain: PAGASA ECMWF; PAGASA ATMO stale'."
    )
    notes: list[str] = Field(default_factory=list)
    range: ValueRangeOut | None = Field(
        description="Only for comparable quantities with 2+ current sources. For directions:"
        " the smallest clockwise arc from `min` to `max`."
    )
    by_source: list[SourceValueOut] = Field(description="Every source's own value (FR-CLI-004).")


class ConsolidatedQuantity(ContractModel):
    quantity: str = Field(examples=["rain"])
    label: str
    unit: str
    priority: list[str] = Field(description="Source ids, first available wins (P-09).")
    slots: list[ConsolidatedSlot]


class Attribution(ContractModel):
    source_id: str
    text: str
    url: str


class ConsolidatedWeather(ContractModel):
    """Best source per value with labelled fallback and a range across sources (P-09).
    Never averaged across sources. Per-source states and provenance: `sources`."""

    match_context_id: UUID
    venue: str
    checked_at: AwareDatetime
    window: CoverageWindow = Field(description="Hourly slots, UTC.")
    sources: list[SourceStatus]
    quantities: list[ConsolidatedQuantity]
    attributions: list[Attribution] = Field(
        description="Must be shown wherever this data appears (Open-Meteo licence)."
    )
