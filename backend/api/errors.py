"""Standard error envelope and exception handlers.

Every error response has the shape::

    {"error": {"code": "...", "message": "...", "request_id": "...", "retry_at": null,
               "details": [...]}}

Messages never include stack traces, secrets, or echoed request values (secure error handling).
When ``retry_at`` is set, a ``Retry-After`` header (whole seconds, rounded up) is sent too.
"""

import logging
import math
from datetime import UTC, datetime
from http import HTTPStatus

import psycopg
from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from psycopg_pool import PoolTimeout
from starlette.exceptions import HTTPException as StarletteHTTPException

from api.middleware.request_id import current_request_id
from api.schemas.common import ErrorBody, ErrorCode, ErrorDetail, ErrorEnvelope

logger = logging.getLogger("pitchy.api")

_STATUS_TO_CODE: dict[int, ErrorCode] = {
    400: ErrorCode.BAD_REQUEST,
    401: ErrorCode.INVALID_SESSION,
    404: ErrorCode.NOT_FOUND,
    405: ErrorCode.METHOD_NOT_ALLOWED,
    409: ErrorCode.CONFLICT,
    413: ErrorCode.PAYLOAD_TOO_LARGE,
    422: ErrorCode.VALIDATION_ERROR,
    429: ErrorCode.RATE_LIMITED,
    501: ErrorCode.NOT_IMPLEMENTED,
    503: ErrorCode.SERVICE_UNAVAILABLE,
}


class ApiError(Exception):
    """Raise from route handlers to return a specific envelope."""

    def __init__(
        self,
        status_code: int,
        code: ErrorCode,
        message: str,
        details: list[ErrorDetail] | None = None,
        retry_at: datetime | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.details = details or []
        self.retry_at = retry_at


def rate_limited(retry_at: datetime) -> ApiError:
    return ApiError(
        429,
        ErrorCode.RATE_LIMITED,
        "Temporary usage limit reached. Try again after retry_at.",
        retry_at=retry_at,
    )


def not_implemented(sprint: str) -> ApiError:
    """Placeholder for contract-draft routes whose behaviour lands in a later sprint."""
    return ApiError(
        501, ErrorCode.NOT_IMPLEMENTED, f"This endpoint is part of the contract draft ({sprint})."
    )


def error_response(
    status_code: int,
    code: ErrorCode,
    message: str,
    details: list[ErrorDetail] | None = None,
    retry_at: datetime | None = None,
) -> JSONResponse:
    envelope = ErrorEnvelope(
        error=ErrorBody(
            code=code,
            message=message,
            request_id=current_request_id(),
            retry_at=retry_at,
            details=details or [],
        )
    )
    headers = {}
    if retry_at is not None:
        seconds = math.ceil((retry_at - datetime.now(UTC)).total_seconds())
        headers["Retry-After"] = str(max(seconds, 0))
    return JSONResponse(
        status_code=status_code, content=envelope.model_dump(mode="json"), headers=headers
    )


async def _api_error_handler(_: Request, exc: ApiError) -> JSONResponse:
    return error_response(exc.status_code, exc.code, exc.message, exc.details, exc.retry_at)


async def _http_error_handler(_: Request, exc: StarletteHTTPException) -> JSONResponse:
    code = _STATUS_TO_CODE.get(exc.status_code, ErrorCode.BAD_REQUEST)
    message = HTTPStatus(exc.status_code).phrase
    return error_response(exc.status_code, code, message)


async def _validation_error_handler(_: Request, exc: RequestValidationError) -> JSONResponse:
    details = [
        ErrorDetail(
            field=".".join(str(part) for part in err.get("loc", ())),
            issue=str(err.get("msg", "Invalid value")),
        )
        for err in exc.errors()
    ]
    return error_response(
        422, ErrorCode.VALIDATION_ERROR, "The request did not pass validation.", details
    )


async def _database_error_handler(_: Request, exc: Exception) -> JSONResponse:
    logger.warning("Database unavailable: %s", type(exc).__name__)  # no URL or credentials
    return error_response(
        503, ErrorCode.SERVICE_UNAVAILABLE, "The database is not reachable right now."
    )


def register_error_handlers(app: FastAPI) -> None:
    app.add_exception_handler(ApiError, _api_error_handler)
    app.add_exception_handler(StarletteHTTPException, _http_error_handler)
    app.add_exception_handler(RequestValidationError, _validation_error_handler)
    app.add_exception_handler(PoolTimeout, _database_error_handler)
    app.add_exception_handler(psycopg.OperationalError, _database_error_handler)
