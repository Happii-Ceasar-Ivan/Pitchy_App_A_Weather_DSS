"""Shared types for weather source adapters (Sprint B2-1).

Every adapter turns one source's response for one venue into ``SourceFetch``: normalized values
plus the raw payload for provenance. Adapters never decide freshness or safety; they only report
what the source said, in UTC, with units, or raise ``SourceError`` with a safe code.
"""

import hashlib
from dataclasses import dataclass, field
from datetime import datetime
from typing import Protocol

from shared.db.records import NewForecastValue


@dataclass(frozen=True)
class Venue:
    """A place we fetch weather for (``locations`` row)."""

    location_id: object  # UUID from the database
    scope_key: str
    name: str
    latitude: float
    longitude: float


@dataclass(frozen=True)
class SourceFetch:
    source_id: str
    venue: Venue
    values: list[NewForecastValue]
    raw_payload: str
    raw_content_type: str = "application/json"
    source_issued_at: datetime | None = None  # model run / init time, when the source says
    notes: list[str] = field(default_factory=list)

    @property
    def raw_payload_sha256(self) -> str:
        return hashlib.sha256(self.raw_payload.encode("utf-8")).hexdigest()


class SourceError(Exception):
    """A source failed in a known way. ``code`` is safe to store and show; ``message`` too."""

    code = "SOURCE_ERROR"

    def __init__(self, message: str, code: str | None = None) -> None:
        super().__init__(message)
        self.message = message
        if code:
            self.code = code


class SourceUnavailableError(SourceError):
    code = "SOURCE_UNAVAILABLE"  # network error, timeout, HTTP error, or source disabled


class SourceResponseChangedError(SourceError):
    code = "SOURCE_RESPONSE_CHANGED"  # response no longer matches what the parser expects


@dataclass(frozen=True)
class FetchFailure:
    """One source id failed for one venue; other source ids of the same adapter may still work."""

    source_id: str
    venue: Venue
    error: SourceError


FetchOutcome = SourceFetch | FetchFailure


class SourceAdapter(Protocol):
    source_ids: tuple[str, ...]  # weather_sources ids this adapter produces

    def fetch(self, venue: Venue) -> list[FetchOutcome]:
        """Fetch one venue: one outcome per produced source id. May raise ``SourceError`` when
        nothing could be fetched at all (e.g. the source is unreachable)."""
        ...


def require(condition: bool, message: str) -> None:
    """Parser guard: anything unexpected means the source changed, never a guess."""
    if not condition:
        raise SourceResponseChangedError(message)
