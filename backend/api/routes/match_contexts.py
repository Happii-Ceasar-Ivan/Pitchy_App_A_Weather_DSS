"""Match context, weather status, ingestion request, assessment and conversation routes.

Contract draft (Sprint B0-4): every handler returns 501 until its sprint implements it.
Anonymous-access protection for ingestion and conversation is OPEN (P-06).
"""

from uuid import UUID

from fastapi import APIRouter, status

from api.errors import not_implemented
from api.schemas.assessment import SafetyAssessment
from api.schemas.common import ERROR_RESPONSES, NOT_FOUND_RESPONSE, ErrorEnvelope
from api.schemas.conversation import ConversationRequest, ConversationResponse
from api.schemas.match import MatchContext, MatchContextCreate
from api.schemas.weather import IngestionJob, WeatherStatus

router = APIRouter(prefix="/match-contexts", tags=["match contexts"], responses=ERROR_RESPONSES)


@router.post("", status_code=status.HTTP_201_CREATED, response_model=MatchContext)
async def create_match_context(body: MatchContextCreate) -> MatchContext:
    """Save the match date/time and venue used for relevance and assessment (FR-MAT-001)."""
    raise not_implemented("Sprint B1")


@router.get("/{match_context_id}", response_model=MatchContext, responses=NOT_FOUND_RESPONSE)
async def get_match_context(match_context_id: UUID) -> MatchContext:
    raise not_implemented("Sprint B1")


@router.get(
    "/{match_context_id}/weather-status",
    response_model=WeatherStatus,
    responses=NOT_FOUND_RESPONSE,
)
async def get_weather_status(match_context_id: UUID) -> WeatherStatus:
    """Per-source freshness and match-time coverage; tells the client if Ingest is needed."""
    raise not_implemented("Sprint B3")


@router.post(
    "/{match_context_id}/ingestions",
    status_code=status.HTTP_202_ACCEPTED,
    response_model=IngestionJob,
    responses={
        **NOT_FOUND_RESPONSE,
        409: {
            "model": ErrorEnvelope,
            "description": "INGESTION_NOT_NEEDED: valid shared data already covers this match.",
        },
    },
)
async def request_ingestion(match_context_id: UUID) -> IngestionJob:
    """Start manual ingestion, or return the job already running for the same scope."""
    raise not_implemented("Sprint B3")


@router.get(
    "/{match_context_id}/assessment",
    response_model=SafetyAssessment,
    responses=NOT_FOUND_RESPONSE,
)
async def get_assessment(match_context_id: UUID) -> SafetyAssessment:
    """Deterministic assessment with inputs, limitations and rule version. Works without AI."""
    raise not_implemented("Sprint B4")


@router.post(
    "/{match_context_id}/conversation",
    response_model=ConversationResponse,
    responses=NOT_FOUND_RESPONSE,
)
async def ask_question(match_context_id: UUID, body: ConversationRequest) -> ConversationResponse:
    """Role-adapted explanation of the active assessment and approved guidance."""
    raise not_implemented("Sprint B5")
