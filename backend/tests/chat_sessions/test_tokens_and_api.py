"""Session tokens, POST /sessions, the per-IP limit and the 401 dependency."""

import logging

from fastapi import Depends
from fastapi.testclient import TestClient

from api.app import API_V1_PREFIX, create_app
from api.deps import get_connect, require_session
from services.chat_sessions import tokens
from shared.settings import Settings
from tests.conftest import requires_db

SECRET = "unit-test-secret"  # noqa: S105
KEY = SECRET.encode()
URL = f"{API_V1_PREFIX}/sessions"


def boom():
    raise AssertionError("the database must not be used")


def make_client(connect, secret=SECRET, **settings) -> TestClient:
    app = create_app(Settings(env="test", session_token_secret=secret, **settings))
    app.dependency_overrides[get_connect] = lambda: connect

    @app.get("/_whoami")
    def whoami(key: bytes = Depends(require_session)) -> dict:
        return {"hash": key.hex()}

    return TestClient(app)


# -- tokens (no database) ------------------------------------------------------------------


def test_token_round_trip():
    t = tokens.issue_token(KEY)
    assert t.startswith("v1.") and len(t) < 512
    assert tokens.verify_token(t, KEY)
    assert len(tokens.token_hash(t, KEY)) == 32
    assert tokens.issue_token(KEY) != t


def test_bad_tokens_rejected():
    t = tokens.issue_token(KEY)
    version, body, tag = t.split(".")
    flipped = ("A" if tag[0] != "A" else "B") + tag[1:]
    other_body = ("A" if body[0] != "A" else "B") + body[1:]
    for bad in (
        f"{version}.{body}.{flipped}",
        f"{version}.{other_body}.{tag}",
        f"v2.{body}.{tag}",
        t + "A" * 600,
        f"{version}.{body}",
        "",
        None,
        t + "=",
    ):
        assert not tokens.verify_token(bad, KEY)
    assert not tokens.verify_token(t, b"another-secret")
    assert not tokens.verify_token(t, None)
    assert not tokens.verify_token(t, b"")


def test_ip_key_hides_ip():
    assert b"10.0.0.1" not in tokens.ip_key("10.0.0.1", KEY)
    assert tokens.ip_key("10.0.0.1", KEY) != tokens.ip_key("10.0.0.2", KEY)


# -- missing secret ------------------------------------------------------------------------


def test_missing_secret_is_503_and_fails_closed():
    c = make_client(boom, secret=None)
    res = c.post(URL)
    assert res.status_code == 503 and res.json()["error"]["code"] == "SERVICE_UNAVAILABLE"
    res = c.get("/_whoami", headers={"X-Session-Token": tokens.issue_token(KEY)})
    assert res.status_code == 503


# -- forged tokens never touch the database --------------------------------------------------


def test_missing_and_forged_token_401_without_db():
    c = make_client(boom)
    t = tokens.issue_token(KEY)
    for headers in ({}, {"X-Session-Token": "junk"}, {"X-Session-Token": t[:-2] + "AA"},
                    {"X-Session-Token": tokens.issue_token(b"other")}):  # fmt: skip
        res = c.get("/_whoami", headers=headers)
        assert res.status_code == 401, headers
        assert res.json()["error"]["code"] == "INVALID_SESSION"


# -- database tests -------------------------------------------------------------------------


@requires_db
def test_create_session_201_and_row(connect, conn):
    c = make_client(connect)
    res = c.post(URL)
    assert res.status_code == 201
    body = res.json()
    assert set(body) == {"token", "created_at"}
    assert tokens.verify_token(body["token"], KEY)
    h = tokens.token_hash(body["token"], KEY)
    assert conn.execute("select count(*) from public.anonymous_sessions where token_hash = %s",
                        (h,)).fetchone()[0] == 1  # fmt: skip
    ok = c.get("/_whoami", headers={"X-Session-Token": body["token"]})
    assert ok.status_code == 200 and ok.json()["hash"] == h.hex()


@requires_db
def test_valid_but_unknown_token_401(connect):
    c = make_client(connect)
    res = c.get("/_whoami", headers={"X-Session-Token": tokens.issue_token(KEY)})
    assert res.status_code == 401 and res.json()["error"]["code"] == "INVALID_SESSION"


@requires_db
def test_per_ip_limit_30_then_429(connect):
    c = make_client(connect)
    for _ in range(30):
        assert c.post(URL).status_code == 201
    res = c.post(URL)
    assert res.status_code == 429
    assert res.json()["error"]["code"] == "RATE_LIMITED"
    assert res.json()["error"]["retry_at"] is not None
    assert int(res.headers["Retry-After"]) > 3000


@requires_db
def test_forwarded_for_hops(connect, conn):
    def fresh(hops):
        # The count is shared in the database (B6), so each case starts from an empty table.
        conn.execute("truncate public.ip_rate_limits")
        return make_client(connect, forwarded_hops=hops, chat_sessions_per_ip_per_hour=1)

    # hops 0: header ignored, everyone is the direct peer
    c = fresh(0)
    assert c.post(URL, headers={"X-Forwarded-For": "1.1.1.1"}).status_code == 201
    assert c.post(URL, headers={"X-Forwarded-For": "2.2.2.2"}).status_code == 429
    # hops 1: last entry counts; a spoofed left side does not help
    c = fresh(1)
    assert c.post(URL, headers={"X-Forwarded-For": "9.9.9.1, 5.5.5.5"}).status_code == 201
    assert c.post(URL, headers={"X-Forwarded-For": "9.9.9.2, 5.5.5.5"}).status_code == 429
    assert c.post(URL, headers={"X-Forwarded-For": "9.9.9.1, 6.6.6.6"}).status_code == 201
    # hops 2: second from the right
    c = fresh(2)
    assert c.post(URL, headers={"X-Forwarded-For": "7.7.7.1, 5.5.5.5, 8.8.8.8"}).status_code == 201
    assert c.post(URL, headers={"X-Forwarded-For": "7.7.7.2, 5.5.5.5, 8.8.8.9"}).status_code == 429
    # header too short or missing: direct peer
    c = fresh(2)
    assert c.post(URL, headers={"X-Forwarded-For": "3.3.3.3"}).status_code == 201
    assert c.post(URL).status_code == 429


@requires_db
def test_session_limit_is_shared_between_app_instances(connect):
    """Two app instances (like two replicas) share one count, and a restart keeps it."""
    a = make_client(connect, chat_sessions_per_ip_per_hour=2)
    b = make_client(connect, chat_sessions_per_ip_per_hour=2)
    assert a.post(URL).status_code == 201
    assert b.post(URL).status_code == 201
    assert a.post(URL).status_code == 429
    assert make_client(connect, chat_sessions_per_ip_per_hour=2).post(URL).status_code == 429


@requires_db
def test_token_never_logged(connect, caplog):
    caplog.set_level(logging.DEBUG)
    c = make_client(connect)
    t = c.post(URL).json()["token"]
    c.get("/_whoami", headers={"X-Session-Token": t})
    c.get("/_whoami", headers={"X-Session-Token": t[:-2] + "AA"})
    text = caplog.text
    body = t.split(".")[1]
    assert t not in text and body not in text
    assert tokens.token_hash(t, KEY).hex() not in text and SECRET not in text
