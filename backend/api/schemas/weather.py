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
    forecast_valid_from: AwareDatetime | None
    forecast_valid_until: AwareDatetime | None
    expires_at: AwareDatetime | None


class SourceStatus(ContractModel):
    source_id: str
    source_name: str
    state: WeatherDataState
    covers_match_time: bool = Field(
        description="False if the cached forecast's validity window does not include kickoff."
    )
    provenance: Provenance | None = Field(description="Null when no record exists.")
    limitations: list[Limitation] = Field(default_factory=list)


class WeatherStatus(ContractModel):
    match_context_id: UUID
    checked_at: AwareDatetime
    sources: list[SourceStatus]
    ingestion_needed: bool = Field(description="Client shows Ingest only when this is true.")
    active_job_id: UUID | None = Field(description="Set while an ingestion job is running.")


class IngestionJobState(StrEnum):
    QUEUED = "queued"
    RUNNING = "running"
    SUCCEEDED = "succeeded"
    FAILED = "failed"
    EXPIRED = "expired"


class IngestionFailure(ContractModel):
    code: str
    message: str = Field(description="Safe summary. Never contains secrets or raw responses.")


class IngestionJob(ContractModel):
    id: UUID
    state: IngestionJobState
    source_ids: list[str]
    created_at: AwareDatetime
    started_at: AwareDatetime | None
    finished_at: AwareDatetime | None
    failures: list[IngestionFailure] = Field(default_factory=list)
    reused_existing_job: bool = Field(
        description="True when another request already started this job (FR-WTH-004)."
    )
