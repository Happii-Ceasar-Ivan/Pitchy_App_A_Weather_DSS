"""Venue list contract (P-07): a fixed list of stadiums the user picks from."""

from pydantic import Field

from api.schemas.common import ContractModel

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


class VenueList(ContractModel):
    venues: list[VenueInfo]
