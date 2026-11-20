"""Ingestion job status route (FR-WTH-004, FR-WTH-006). Contract draft: returns 501."""

from uuid import UUID

from fastapi import APIRouter

from api.errors import not_implemented
from api.schemas.common import ERROR_RESPONSES, NOT_FOUND_RESPONSE
from api.schemas.weather import IngestionJob

router = APIRouter(prefix="/ingestions", tags=["ingestion"], responses=ERROR_RESPONSES)


@router.get("/{job_id}", response_model=IngestionJob, responses=NOT_FOUND_RESPONSE)
async def get_ingestion_job(job_id: UUID) -> IngestionJob:
    """Poll a job until it succeeds, fails or expires."""
    raise not_implemented("Sprint B3")
