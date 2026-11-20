"""Liveness endpoint. Reports only that the API process is up; it makes no claim about
weather data freshness, ingestion state, or safety-engine readiness."""

from typing import Literal

from fastapi import APIRouter

from api.schemas.common import ERROR_RESPONSES, ContractModel

router = APIRouter(tags=["health"])


class HealthResponse(ContractModel):
    status: Literal["ok"] = "ok"


@router.get("/health", response_model=HealthResponse, responses={500: ERROR_RESPONSES[500]})
async def health() -> HealthResponse:
    return HealthResponse()
