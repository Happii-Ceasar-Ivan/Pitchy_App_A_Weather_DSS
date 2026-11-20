"""Match context contract (FR-MAT-001, FR-MAT-003).

Venue selection and time-zone handling are OPEN (P-07). The draft takes coordinates plus an
optional display name; venue search/geocoding is not part of this contract yet.
"""

from uuid import UUID

from pydantic import AwareDatetime, Field

from api.schemas.common import ContractModel


class Venue(ContractModel):
    name: str | None = Field(default=None, max_length=200)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    pitch_surface: str | None = Field(
        default=None,
        max_length=50,
        description="Optional pitch metadata. Allowed values are not decided (P-07).",
    )


class MatchContextCreate(ContractModel):
    kickoff_at: AwareDatetime = Field(description="Match start, ISO 8601 with UTC offset.")
    venue: Venue


class MatchContext(MatchContextCreate):
    id: UUID
    created_at: AwareDatetime
    updated_at: AwareDatetime
