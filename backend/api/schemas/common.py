"""Shared contract types: error envelope and common value objects.

Contract conventions (API v1, draft):
- Base path ``/api/v1``. Breaking changes require a new major path version.
- JSON bodies, UTF-8. All timestamps are ISO 8601 with an explicit UTC offset.
- Every response carries ``X-Request-ID``. Errors use :class:`ErrorEnvelope`.
"""

from enum import StrEnum
from typing import Literal

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field


class ContractModel(BaseModel):
    """Base for all request/response bodies: unknown fields are rejected."""

    model_config = ConfigDict(extra="forbid")


class ErrorCode(StrEnum):
    BAD_REQUEST = "BAD_REQUEST"
    INVALID_SESSION = "INVALID_SESSION"
    VALIDATION_ERROR = "VALIDATION_ERROR"
    NOT_FOUND = "NOT_FOUND"
    METHOD_NOT_ALLOWED = "METHOD_NOT_ALLOWED"
    CONFLICT = "CONFLICT"
    INGESTION_NOT_NEEDED = "INGESTION_NOT_NEEDED"
    PAYLOAD_TOO_LARGE = "PAYLOAD_TOO_LARGE"
    RATE_LIMITED = "RATE_LIMITED"
    NOT_IMPLEMENTED = "NOT_IMPLEMENTED"
    SERVICE_UNAVAILABLE = "SERVICE_UNAVAILABLE"
    INTERNAL_ERROR = "INTERNAL_ERROR"


class ErrorDetail(ContractModel):
    field: str | None = Field(default=None, description="Dotted location of the invalid input.")
    issue: str


class ErrorBody(ContractModel):
    code: ErrorCode
    message: str = Field(description="Human-readable summary. Never contains internal details.")
    request_id: str | None = Field(description="Matches the X-Request-ID response header.")
    retry_at: AwareDatetime | None = Field(
        default=None,
        description="When a RATE_LIMITED request may be retried (UTC). Also sent as Retry-After.",
    )
    details: list[ErrorDetail] = Field(default_factory=list)


class ErrorEnvelope(ContractModel):
    error: ErrorBody


Severity = Literal["advisory", "warning", "danger"]
"""Display grade of a rule level, set in the rules file (P-19). The app colours from it; it never
changes a level or a classification."""

SEVERITY_DESCRIPTION = (
    "How strongly to show this level (advisory, warning or danger), from the rules file (P-19). "
    "Display only; null when the rules give none."
)


class Limitation(ContractModel):
    """A data or method limitation the client must show (FR-SAF-004, FR-AGT-005)."""

    code: str = Field(examples=["STALE_INPUT", "MISSING_INPUT", "CONFLICTING_SOURCES"])
    message: str = Field(description="Plain-language text to show. Never contains technical codes.")
    detail_code: str | None = Field(
        default=None,
        examples=["HTTP_503"],
        description="Technical cause for support or logs (e.g. the source's error code). "
        "Optional; not meant for display.",
    )


class GuidanceReference(ContractModel):
    """Reference to an approved protocol document (RAG knowledge base)."""

    document_id: str
    title: str
    authority: str = Field(description="Issuing body, e.g. the football authority.")
    version: str = Field(description="Version or date of the approved document.")
    section: str | None = None


# Shared responses documented on every v1 route.
ERROR_RESPONSES: dict[int | str, dict] = {
    422: {"model": ErrorEnvelope, "description": "Validation error"},
    429: {
        "model": ErrorEnvelope,
        "description": "RATE_LIMITED. Body has retry_at; Retry-After header gives seconds.",
        "headers": {"Retry-After": {"schema": {"type": "integer"}}},
    },
    500: {"model": ErrorEnvelope, "description": "Unexpected server error"},
    501: {"model": ErrorEnvelope, "description": "Not implemented yet (contract draft)"},
    503: {
        "model": ErrorEnvelope,
        "description": "SERVICE_UNAVAILABLE: the database is not configured or not reachable.",
    },
}

INVALID_SESSION_RESPONSE: dict[int | str, dict] = {
    401: {
        "model": ErrorEnvelope,
        "description": "INVALID_SESSION: token missing, forged, unknown or expired.",
    },
}

NOT_FOUND_RESPONSE: dict[int | str, dict] = {
    404: {"model": ErrorEnvelope, "description": "Resource not found"},
}
