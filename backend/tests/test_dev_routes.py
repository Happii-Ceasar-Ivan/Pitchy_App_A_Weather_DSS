"""Dev routes must only exist locally in development with the explicit flag."""

from fastapi.testclient import TestClient

from api.app import API_V1_PREFIX, create_app
from shared.settings import Settings


def client(env: str, flag: bool, host: str = "testclient") -> TestClient:
    app = create_app(Settings(env=env, enable_dev_routes=flag))
    return TestClient(app, client=(host, 50000))


def has_dev_routes(c: TestClient) -> bool:
    paths = c.app.openapi()["paths"] if c.app.openapi_url else {}
    return any(p.startswith(f"{API_V1_PREFIX}/dev") for p in paths) or any(
        getattr(r, "path", "").startswith(f"{API_V1_PREFIX}/dev") for r in c.app.routes
    )


def test_absent_without_flag_or_outside_development() -> None:
    assert not has_dev_routes(client("development", False))
    assert not has_dev_routes(client("test", True))
    assert not has_dev_routes(client("production", True))


def test_present_in_development_with_flag() -> None:
    assert has_dev_routes(client("development", True))


def test_remote_requests_get_not_found() -> None:
    remote = client("development", True, host="203.0.113.7")
    res = remote.get(f"{API_V1_PREFIX}/dev/venues")
    assert res.status_code == 404
    assert res.json()["error"]["code"] == "NOT_FOUND"
