"""Conversational query contract (FR-AGT-001..006).

The role only changes explanation style (P-03, FR-AGT-003). The response never carries a
classification of its own: hazard state comes from the referenced assessment.
"""

from enum import StrEnum
from typing import Literal
from uuid import UUID

from pydantic import AwareDatetime, Field

from api.schemas.common import ContractModel, GuidanceReference, Limitation

QUESTION_MAX_CHARS = 2000


class ConversationRole(StrEnum):
    """Conversational context only, not an authenticated account role (P-03)."""

    COACH = "coach"
    MATCH_OFFICIAL = "match_official"
    REFEREE = "referee"
    MEDICAL_STAFF = "medical_staff"
    SPECTATOR = "spectator"


class ConversationRequest(ContractModel):
    role: ConversationRole
    question: str = Field(min_length=1, max_length=QUESTION_MAX_CHARS)


class ConversationResponse(ContractModel):
    match_context_id: UUID
    assessment_id: UUID | None = Field(description="Assessment the answer explains, if any.")
    role: ConversationRole
    generation: Literal["generated", "unavailable"] = Field(
        description="'unavailable' when no AI provider answered (FR-AGT-006)."
    )
    answer: str | None = Field(description="AI-generated explanation. Not an official decision.")
    references: list[GuidanceReference] = Field(default_factory=list)
    limitations: list[Limitation] = Field(default_factory=list)
    responded_at: AwareDatetime
