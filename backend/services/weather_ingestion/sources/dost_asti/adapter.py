"""DOST-ASTI adapter placeholder (DEC-01). The feed is not decided yet.

The source stays disabled; if it is ever asked for data it reports itself unavailable, so the
app shows DOST-ASTI as Unavailable instead of inventing anything.
"""

from services.weather_ingestion.sources.base import (
    FetchFailure,
    FetchOutcome,
    SourceUnavailableError,
    Venue,
)

SOURCE_ID = "dost_asti"


class DostAstiAdapter:
    source_ids = (SOURCE_ID,)

    def fetch(self, venue: Venue) -> list[FetchOutcome]:
        error = SourceUnavailableError("DOST-ASTI feed not configured yet.", "NOT_CONFIGURED")
        return [FetchFailure(SOURCE_ID, venue, error)]
