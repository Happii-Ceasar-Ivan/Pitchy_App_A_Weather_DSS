"""Deterministic safety assessment for a match (B4). Works without any AI provider.

The assessment is built by services.safety_engine.assessment_service (shared with the chat route).
"""

from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends

from api.deps import get_adapter_groups, get_connect, get_lightning_fetcher, get_settings_dep
from api.schemas.assessment import SafetyAssessment
from api.schemas.common import ERROR_RESPONSES, NOT_FOUND_RESPONSE
from services.safety_engine.assessment_service import current_assessment
from shared.db.pool import ConnectionFactory
from shared.settings import Settings

router = APIRouter(prefix="/match-contexts", tags=["assessment"], responses=ERROR_RESPONSES)


@router.get(
    "/{match_context_id}/assessment",
    response_model=SafetyAssessment,
    responses=NOT_FOUND_RESPONSE,
)
def get_assessment(
    match_context_id: UUID,
    connect: Annotated[ConnectionFactory, Depends(get_connect)],
    settings: Annotated[Settings, Depends(get_settings_dep)],
    groups: Annotated[list, Depends(get_adapter_groups)],
    fetch_lightning=Depends(get_lightning_fetcher),  # noqa: B008
) -> SafetyAssessment:
    """Deterministic assessment with inputs, limitations and rule version (FR-SAF-001..005).

    Heat: WBGT estimate (Liljegren) at 90 and 60 minutes before kickoff; the level comes from the
    approved rules for the match's age group, only from current forecast data. Lightning: the
    latest shared Xweather check and the AFC 10 km level. Rain: no approved rule. Official PAGASA
    alerts are listed as issued. Pitchy never makes the official decision."""
    return current_assessment(connect, settings, groups, fetch_lightning, match_context_id)
