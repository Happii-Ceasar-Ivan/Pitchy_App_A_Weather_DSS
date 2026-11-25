"""Venue list (P-07): public and read-only. Venues are reference data from migrations."""

from typing import Annotated

from fastapi import APIRouter, Depends

from api.deps import get_connect
from api.schemas.common import ERROR_RESPONSES
from api.schemas.venue import VenueInfo, VenueList
from shared.db.pool import ConnectionFactory
from shared.db.repositories import PgLocationRepository

router = APIRouter(prefix="/venues", tags=["venues"], responses=ERROR_RESPONSES)


@router.get("", response_model=VenueList)
def list_venues(connect: Annotated[ConnectionFactory, Depends(get_connect)]) -> VenueList:
    """The stadiums a match can be planned at. Clients send a `scope_key`, never coordinates."""
    return VenueList(
        venues=[VenueInfo.from_location(v) for v in PgLocationRepository(connect).list_all()]
    )
