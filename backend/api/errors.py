"""Standard error envelope and exception handlers.

Every error response has the shape::

    {"error": {"code": "...", "message": "...", "request_id": "...", "details": [...]}}

Messages never include stack traces, secrets, or echoed request values (secure error handling).
"""

from http import HTTPStatus

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException

from api.middleware.request_id import current_request_id
from api.schemas.common import ErrorBody, ErrorCode, ErrorDetail, ErrorEnvelope

_STATUS_TO_CODE: dict[int, ErrorCode] = {
    400: ErrorCode.BAD_REQUEST,
    404: ErrorCode.NOT_FOUND,
    405: ErrorCode.METHOD_NOT_ALLOWED,
    409: ErrorCode.CONFLICT,
    413: ErrorCode.PAYLOAD_TOO_LARGE,
    422: ErrorCode.VALIDATION_ERROR,
    429: ErrorCode.RATE_LIMITED,
    501: ErrorCode.NOT_IMPLEMENTED,
}


class ApiError(Exception):
    """Raise from route handlers to return a specific envelope."""

    def __init__(
        self,
        status_code: int,
        code: ErrorCode,
        message: str,
        details: list[ErrorDetail] | None = None,
    ) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.code = code
        self.message = message
        self.details = details or []


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
) -> JSONResponse:
    envelope = ErrorEnvelope(
        error=ErrorBody(
            code=code,
            message=message,
            request_id=current_request_id(),
            details=details or [],
        )
    )
    return JSONResponse(status_code=status_code, content=envelope.model_dump(mode="json"))


async def _api_error_handler(_: Request, exc: ApiError) -> JSONResponse:
    return error_response(exc.status_code, exc.code, exc.message, exc.details)


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


def register_error_handlers(app: FastAPI) -> None:
    app.add_exception_handler(ApiError, _api_error_handler)
    app.add_exception_handler(StarletteHTTPException, _http_error_handler)
    app.add_exception_handler(RequestValidationError, _validation_error_handler)
