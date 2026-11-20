from datetime import UTC, datetime, timedelta

from fastapi import Query
from fastapi.testclient import TestClient

from api.app import API_V1_PREFIX, create_app
from api.errors import ApiError, rate_limited
from api.schemas.common import ErrorCode
from shared.settings import Settings


def _client(env: str = "test") -> TestClient:
    app = create_app(Settings(env=env))

    @app.get(f"{API_V1_PREFIX}/_boom")
    async def boom() -> None:
        raise RuntimeError("secret internal detail")

    @app.get(f"{API_V1_PREFIX}/_conflict")
    async def conflict() -> None:
        raise ApiError(409, ErrorCode.CONFLICT, "Ingestion already running.")

    @app.get(f"{API_V1_PREFIX}/_limited")
    async def limited() -> None:
        raise rate_limited(datetime.now(UTC) + timedelta(minutes=20))

    @app.get(f"{API_V1_PREFIX}/_validate")
    async def validate(n: int = Query()) -> dict[str, int]:
        return {"n": n}

    return TestClient(app, raise_server_exceptions=False)


def test_health_ok_with_generated_request_id() -> None:
    res = _client().get(f"{API_V1_PREFIX}/health")
    assert res.status_code == 200
    assert res.json() == {"status": "ok"}
    assert len(res.headers["X-Request-ID"]) == 32


def test_safe_client_request_id_is_echoed() -> None:
    res = _client().get(f"{API_V1_PREFIX}/health", headers={"X-Request-ID": "abc-123.x_y"})
    assert res.headers["X-Request-ID"] == "abc-123.x_y"


def test_unsafe_client_request_id_is_replaced() -> None:
    res = _client().get(f"{API_V1_PREFIX}/health", headers={"X-Request-ID": "bad id\twith space"})
    assert res.headers["X-Request-ID"] != "bad id\twith space"
    assert len(res.headers["X-Request-ID"]) == 32


def test_not_found_uses_envelope() -> None:
    res = _client().get(f"{API_V1_PREFIX}/nope")
    body = res.json()["error"]
    assert res.status_code == 404
    assert body["code"] == "NOT_FOUND"
    assert body["request_id"] == res.headers["X-Request-ID"]


def test_validation_error_envelope_has_details() -> None:
    res = _client().get(f"{API_V1_PREFIX}/_validate", params={"n": "x"})
    body = res.json()["error"]
    assert res.status_code == 422
    assert body["code"] == "VALIDATION_ERROR"
    assert body["details"][0]["field"] == "query.n"


def test_api_error_envelope() -> None:
    res = _client().get(f"{API_V1_PREFIX}/_conflict")
    assert res.status_code == 409
    assert res.json()["error"]["code"] == "CONFLICT"


def test_rate_limited_envelope_has_retry_at_and_header() -> None:
    res = _client().get(f"{API_V1_PREFIX}/_limited")
    body = res.json()["error"]
    assert res.status_code == 429
    assert body["code"] == "RATE_LIMITED"
    retry_at = datetime.fromisoformat(body["retry_at"])
    assert retry_at.tzinfo is not None
    assert 1190 <= int(res.headers["Retry-After"]) <= 1200


def test_non_rate_limit_errors_have_null_retry_at() -> None:
    res = _client().get(f"{API_V1_PREFIX}/_conflict")
    assert res.json()["error"]["retry_at"] is None
    assert "Retry-After" not in res.headers


def test_unhandled_error_hides_internals() -> None:
    res = _client().get(f"{API_V1_PREFIX}/_boom")
    assert res.status_code == 500
    assert res.json()["error"]["code"] == "INTERNAL_ERROR"
    assert "secret" not in res.text
    assert res.json()["error"]["request_id"] == res.headers["X-Request-ID"]


def test_docs_disabled_in_production() -> None:
    assert _client("production").get(f"{API_V1_PREFIX}/openapi.json").status_code == 404
    assert _client("test").get(f"{API_V1_PREFIX}/openapi.json").status_code == 200
