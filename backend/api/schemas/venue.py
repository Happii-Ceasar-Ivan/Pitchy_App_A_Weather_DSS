"""Venue list contract (P-07): a fixed list of stadiums the user picks from."""

from pydantic import Field

from api.schemas.common import ContractModel
from shared.db.records import Location

VENUE_KEY_PATTERN = r"^[a-z][a-z0-9_]{1,63}$"


class VenueInfo(ContractModel):
    scope_key: str = Field(
        pattern=VENUE_KEY_PATTERN,
        examples=["rizal_memorial"],
        description="Stable venue key. Send it as `venue` when creating a match context.",
    )
    name: str
    latitude: float = Field(ge=-90, le=90, description="Coordinates used for every source.")
    longitude: float = Field(ge=-180, le=180)

    @classmethod
    def from_location(cls, location: Location) -> VenueInfo:
        return cls(
            scope_key=location.scope_key,
            name=location.name or location.scope_key,
            latitude=location.latitude,
            longitude=location.longitude,
        )


class VenueList(ContractModel):
    venues: list[VenueInfo]
