"""Match context contract (FR-MAT-001, FR-MAT-003).

The venue is picked from ``GET /venues`` and sent as its scope key (P-07, team decision
2026-11-22). The backend uses that venue's stored coordinates; clients never send coordinates.
How local time is displayed is still OPEN; the API stores and returns UTC with an offset.
"""

from uuid import UUID

from pydantic import AwareDatetime, Field

from api.schemas.common import ContractModel
from api.schemas.venue import VENUE_KEY_PATTERN, VenueInfo


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


class MatchContext(ContractModel):
    id: UUID
    kickoff_at: AwareDatetime
    venue: VenueInfo
    pitch_surface: str | None
    created_at: AwareDatetime
    updated_at: AwareDatetime
