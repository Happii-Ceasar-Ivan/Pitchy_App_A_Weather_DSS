"""Shared contract types: error envelope and common value objects.

Contract conventions (API v1, draft):
- Base path ``/api/v1``. Breaking changes require a new major path version.
- JSON bodies, UTF-8. All timestamps are ISO 8601 with an explicit UTC offset.
- Every response carries ``X-Request-ID``. Errors use :class:`ErrorEnvelope`.
"""

from enum import StrEnum

from pydantic import BaseModel, ConfigDict, Field


class ContractModel(BaseModel):
    """Base for all request/response bodies: unknown fields are rejected."""

    model_config = ConfigDict(extra="forbid")


class ErrorCode(StrEnum):
    BAD_REQUEST = "BAD_REQUEST"
    VALIDATION_ERROR = "VALIDATION_ERROR"
    NOT_FOUND = "NOT_FOUND"
    METHOD_NOT_ALLOWED = "METHOD_NOT_ALLOWED"
    CONFLICT = "CONFLICT"
    INGESTION_NOT_NEEDED = "INGESTION_NOT_NEEDED"
    PAYLOAD_TOO_LARGE = "PAYLOAD_TOO_LARGE"
    RATE_LIMITED = "RATE_LIMITED"
    NOT_IMPLEMENTED = "NOT_IMPLEMENTED"
    INTERNAL_ERROR = "INTERNAL_ERROR"


class ErrorDetail(ContractModel):
    field: str | None = Field(default=None, description="Dotted location of the invalid input.")
    issue: str


class ErrorBody(ContractModel):
    code: ErrorCode
    message: str = Field(description="Human-readable summary. Never contains internal details.")
    request_id: str | None = Field(description="Matches the X-Request-ID response header.")
    details: list[ErrorDetail] = Field(default_factory=list)


class ErrorEnvelope(ContractModel):
    error: ErrorBody


class Limitation(ContractModel):
    """A data or method limitation the client must show (FR-SAF-004, FR-AGT-005)."""

    code: str = Field(examples=["STALE_INPUT", "MISSING_INPUT", "CONFLICTING_SOURCES"])
    message: str


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
    429: {"model": ErrorEnvelope, "description": "Rate limited (limits are set in Sprint B6)"},
    500: {"model": ErrorEnvelope, "description": "Unexpected server error"},
    501: {"model": ErrorEnvelope, "description": "Not implemented yet (contract draft)"},
}

NOT_FOUND_RESPONSE: dict[int | str, dict] = {
    404: {"model": ErrorEnvelope, "description": "Resource not found"},
}
