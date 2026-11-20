import pytest
from fastapi.testclient import TestClient

from api.app import API_V1_PREFIX, create_app
from scripts.export_openapi import CONTRACT_PATH, render_contract
from shared.settings import Settings

MATCH_ID = "00000000-0000-4000-8000-000000000001"


@pytest.fixture
def client() -> TestClient:
    return TestClient(create_app(Settings(env="test")))


def test_committed_contract_is_up_to_date() -> None:
    committed = CONTRACT_PATH.read_text(encoding="utf-8")
    assert committed == render_contract(), (
        "contract/openapi.v1.json is stale: run `uv run python scripts/export_openapi.py`"
    )


@pytest.mark.parametrize(
    ("method", "path", "body"),
    [
        (
            "post",
            "/match-contexts",
            {
                "kickoff_at": "2026-12-01T15:00:00+08:00",
                "venue": {"latitude": 14.6, "longitude": 121.0},
            },
        ),
        ("get", f"/match-contexts/{MATCH_ID}", None),
        ("get", f"/match-contexts/{MATCH_ID}/weather-status", None),
        ("post", f"/match-contexts/{MATCH_ID}/ingestions", None),
        ("get", f"/match-contexts/{MATCH_ID}/assessment", None),
        ("post", f"/match-contexts/{MATCH_ID}/conversation", {"role": "coach", "question": "Hi"}),
        ("get", f"/ingestions/{MATCH_ID}", None),
    ],
)
def test_draft_routes_return_not_implemented(
    client: TestClient, method: str, path: str, body: dict | None
) -> None:
    res = client.request(method, API_V1_PREFIX + path, json=body)
    assert res.status_code == 501
    assert res.json()["error"]["code"] == "NOT_IMPLEMENTED"


def test_kickoff_without_utc_offset_is_rejected(client: TestClient) -> None:
    res = client.post(
        f"{API_V1_PREFIX}/match-contexts",
        json={"kickoff_at": "2026-12-01T15:00:00", "venue": {"latitude": 14.6, "longitude": 121.0}},
    )
    assert res.status_code == 422


def test_unknown_role_and_extra_fields_are_rejected(client: TestClient) -> None:
    url = f"{API_V1_PREFIX}/match-contexts/{MATCH_ID}/conversation"
    assert client.post(url, json={"role": "admin", "question": "Hi"}).status_code == 422
    extra = {"role": "coach", "question": "Hi", "classification": "safe"}
    assert client.post(url, json=extra).status_code == 422
