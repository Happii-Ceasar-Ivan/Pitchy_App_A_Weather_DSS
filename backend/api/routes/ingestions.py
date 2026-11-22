"""Ingestion job status route (FR-WTH-004, FR-WTH-006)."""

from datetime import UTC, datetime
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends

from api.deps import get_adapter_groups, get_connect
from api.errors import ApiError
from api.schemas.common import ERROR_RESPONSES, NOT_FOUND_RESPONSE, ErrorCode
from api.schemas.weather import IngestionFailure, IngestionJob
from services.weather_ingestion.jobs.manual import source_ids_for_job
from shared.db.pool import ConnectionFactory
from shared.db.repositories import (
    PgForecastRepository,
    PgIngestionJobRepository,
    PgLocationRepository,
    PgWeatherSourceRepository,
)

router = APIRouter(prefix="/ingestions", tags=["ingestion"], responses=ERROR_RESPONSES)


@router.get("/{job_id}", response_model=IngestionJob, responses=NOT_FOUND_RESPONSE)
def get_ingestion_job(
    job_id: UUID,
    connect: Annotated[ConnectionFactory, Depends(get_connect)],
    groups: Annotated[list, Depends(get_adapter_groups)],
) -> IngestionJob:
    """Poll a job until it succeeds, fails or expires. A job that stops renewing its lease is
    reported ``expired`` once another request takes over its scope."""
    job = PgIngestionJobRepository(connect).get(job_id)
    if job is None:
        raise ApiError(404, ErrorCode.NOT_FOUND, "Ingestion job not found.")
    location = PgLocationRepository(connect).get(job.location_id)
    enabled = {s.id for s in PgWeatherSourceRepository(connect).list_enabled()}
    failures = [
        IngestionFailure(
            source_id=f.source_id,
            code=f.error_code or "SOURCE_ERROR",
            message=f.error_summary or "The source request failed.",
        )
        for f in PgForecastRepository(connect).failures_for_job(job.id)
    ]
    if not failures and job.failure_code:
        failures = [
            IngestionFailure(code=job.failure_code, message=job.failure_message or "Job failed.")
        ]
    state = job.state
    if state in ("queued", "running") and job.lease_expires_at <= datetime.now(UTC):
        state = "expired"  # stopped renewing its lease; the next request takes over the scope
        failures = failures or [
            IngestionFailure(code="LEASE_EXPIRED", message="The job stopped renewing its lease.")
        ]
    return IngestionJob(
        id=job.id,
        state=state,
        venue=location.scope_key,
        source_ids=source_ids_for_job(job, groups, enabled),
        created_at=job.requested_at,
        started_at=job.started_at,
        finished_at=job.finished_at,
        failures=failures,
        reused_existing_job=False,
    )
