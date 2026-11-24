import pytest
from fastapi.testclient import TestClient

from api.app import API_V1_PREFIX, create_app
from api.deps import get_connect
from scripts.export_openapi import CONTRACT_PATH, render_contract
from shared.settings import Settings

MATCH_ID = "00000000-0000-4000-8000-000000000001"
SESSION = {"X-Session-Token": "test-token"}


def _no_database():
    raise AssertionError("contract tests must not reach a database")


@pytest.fixture
def client() -> TestClient:
    app = create_app(Settings(env="test"))
    app.dependency_overrides[get_connect] = lambda: _no_database
    return TestClient(app)


def test_committed_contract_is_up_to_date() -> None:
    committed = CONTRACT_PATH.read_text(encoding="utf-8")
    assert committed == render_contract(), (
        "contract/openapi.v1.json is stale: run `uv run python scripts/export_openapi.py`"
    )


@pytest.mark.parametrize(
    ("method", "path", "body"),
    [
        ("post", f"/match-contexts/{MATCH_ID}/conversation", {"role": "coach", "question": "Hi"}),
        # POST /sessions is built (B5 WP2); its tests are in tests/chat_sessions/.
    ],
)
def test_draft_routes_return_not_implemented(
    client: TestClient, method: str, path: str, body: dict | None
) -> None:
    res = client.request(method, API_V1_PREFIX + path, json=body, headers=SESSION)
    assert res.status_code == 501
    assert res.json()["error"]["code"] == "NOT_IMPLEMENTED"


def test_kickoff_without_utc_offset_is_rejected(client: TestClient) -> None:
    res = client.post(
        f"{API_V1_PREFIX}/match-contexts",
        json={"kickoff_at": "2026-12-01T15:00:00", "venue": "rizal_memorial"},
    )
    assert res.status_code == 422


def test_coordinates_are_not_accepted_as_a_venue(client: TestClient) -> None:
    res = client.post(
        f"{API_V1_PREFIX}/match-contexts",
        json={"kickoff_at": "2026-12-01T15:00:00+08:00",
              "venue": {"latitude": 14.6, "longitude": 121.0}},
    )  # fmt: skip
    assert res.status_code == 422


def test_test_environment_never_opens_the_configured_database() -> None:
    res = TestClient(create_app(Settings(env="test"))).get(f"{API_V1_PREFIX}/venues")
    assert res.status_code == 503
    assert res.json()["error"]["code"] == "SERVICE_UNAVAILABLE"


def test_unknown_role_and_extra_fields_are_rejected(client: TestClient) -> None:
    url = f"{API_V1_PREFIX}/match-contexts/{MATCH_ID}/conversation"
    bad_role = {"role": "admin", "question": "Hi"}
    assert client.post(url, json=bad_role, headers=SESSION).status_code == 422
    extra = {"role": "coach", "question": "Hi", "classification": "safe"}
    assert client.post(url, json=extra, headers=SESSION).status_code == 422


def test_conversation_requires_session_token(client: TestClient) -> None:
    url = f"{API_V1_PREFIX}/match-contexts/{MATCH_ID}/conversation"
    res = client.post(url, json={"role": "coach", "question": "Hi"})
    assert res.status_code == 422
    assert res.json()["error"]["details"][0]["field"] == "header.X-Session-Token"
