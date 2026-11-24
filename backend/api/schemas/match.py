"""Match context contract (FR-MAT-001, FR-MAT-003).

The venue is picked from ``GET /venues`` and sent as its scope key (P-07, team decision
2026-11-22). The backend uses that venue's stored coordinates; clients never send coordinates.
How local time is displayed is still OPEN; the API stores and returns UTC with an offset.
"""

from enum import StrEnum
from uuid import UUID

from pydantic import AwareDatetime, Field

from api.schemas.common import ContractModel
from api.schemas.venue import VENUE_KEY_PATTERN, VenueInfo


class AgeGroup(StrEnum):
    """Selects the heat level set in rules.yaml (team decision 2026-11-24)."""

    SENIOR = "senior"  # FIFA / AFC cooling-break level, WBGT 32 °C
    YOUTH_U20 = "youth_u20"  # AFC under-20 and younger competitions, WBGT 28 °C


class MatchContextCreate(ContractModel):
    kickoff_at: AwareDatetime = Field(description="Match start, ISO 8601 with UTC offset.")
    venue: str = Field(
        pattern=VENUE_KEY_PATTERN,
        examples=["rizal_memorial"],
        description="A `scope_key` from GET /venues. Unknown keys are rejected (422).",
    )
    pitch_surface: str | None = Field(
        default=None,
        max_length=50,
        description="Optional pitch metadata. Allowed values are not decided (P-07).",
    )
    age_group: AgeGroup = Field(
        default=AgeGroup.SENIOR,
        description="Competition age group. Selects the heat level set; shown with the assessment.",
    )


class MatchContext(ContractModel):
    id: UUID
    kickoff_at: AwareDatetime
    venue: VenueInfo
    pitch_surface: str | None
    age_group: AgeGroup
    created_at: AwareDatetime
    updated_at: AwareDatetime
