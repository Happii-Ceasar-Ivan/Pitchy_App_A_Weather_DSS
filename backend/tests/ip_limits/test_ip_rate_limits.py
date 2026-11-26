"""B6 shared per-IP limits: the database limiter, its retention, and the four limited routes."""

import threading
from datetime import timedelta
from uuid import uuid4

import psycopg
import pytest
from fastapi.testclient import TestClient

from api.app import API_V1_PREFIX, create_app
from api.deps import get_adapter_groups, get_connect, get_ingestion_executor
from services.chat_sessions import tokens
from services.ip_limits import (
    ASSESSMENT_READ,
    INGESTION_REQUEST,
    MATCH_CREATE,
    SESSION_CREATE,
    IpLimitRule,
    IpRateLimiter,
    rules_from_settings,
)
from shared.settings import Settings
from tests.conftest import requires_db

pytestmark = requires_db

API = API_V1_PREFIX
KEY_A = b"a" * 32
KEY_B = b"b" * 32
HOUR = timedelta(hours=1)
MATCH_BODY = {"kickoff_at": "2026-12-01T15:00:00+08:00", "venue": "rizal_memorial"}


def make_client(connect, **settings) -> TestClient:
    app = create_app(Settings(env="test", **settings))
    app.dependency_overrides[get_connect] = lambda: connect
    app.dependency_overrides[get_adapter_groups] = lambda: []
    app.dependency_overrides[get_ingestion_executor] = lambda: None
    return TestClient(app)


# -- limiter --------------------------------------------------------------------------------


def test_rules_use_the_approved_values():
    rules = rules_from_settings(Settings(env="test"))
    assert (rules[SESSION_CREATE].max_requests, rules[SESSION_CREATE].window) == (30, HOUR)
    assert rules[ASSESSMENT_READ].max_requests == 120
    assert rules[ASSESSMENT_READ].window == timedelta(minutes=10)
    assert (rules[MATCH_CREATE].max_requests, rules[MATCH_CREATE].window) == (20, HOUR)
    assert (rules[INGESTION_REQUEST].max_requests, rules[INGESTION_REQUEST].window) == (10, HOUR)


def test_limit_then_retry_at_and_independent_keys_and_scopes(connect, conn):
    lim = IpRateLimiter(connect)
    rule = IpLimitRule(MATCH_CREATE, 2, HOUR)
    assert lim.hit(rule, KEY_A) is None
    assert lim.hit(rule, KEY_A) is None
    first = conn.execute(
        "select hit_times[1] from public.ip_rate_limits where scope = %s", (MATCH_CREATE,)
    ).fetchone()[0]
    retry = lim.hit(rule, KEY_A)
    assert retry is not None and retry > first + HOUR
    assert lim.hit(rule, KEY_B) is None  # another IP
    assert lim.hit(IpLimitRule(ASSESSMENT_READ, 2, HOUR), KEY_A) is None  # another route
    # A rejected request is not stored, so the array never grows past the limit.
    times = conn.execute(
        "select cardinality(hit_times) from public.ip_rate_limits where scope = %s and ip_key = %s",
        (MATCH_CREATE, KEY_A),
    ).fetchone()[0]
    assert times == 2


def test_old_hits_leave_the_window(connect, conn):
    lim = IpRateLimiter(connect)
    rule = IpLimitRule(MATCH_CREATE, 1, HOUR)
    assert lim.hit(rule, KEY_A) is None
    assert lim.hit(rule, KEY_A) is not None
    conn.execute(
        "update public.ip_rate_limits set hit_times = array[now() - interval '61 minutes']"
    )
    assert lim.hit(rule, KEY_A) is None


def test_concurrent_hits_never_pass_the_limit(connect):
    lim = IpRateLimiter(connect)
    rule = IpLimitRule(ASSESSMENT_READ, 5, HOUR)
    results: list = []
    lock = threading.Lock()

    def worker():
        r = lim.hit(rule, KEY_A)
        with lock:
            results.append(r)

    threads = [threading.Thread(target=worker) for _ in range(12)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    assert sum(r is None for r in results) == 5


def test_purge_removes_only_idle_rows_and_app_cannot_delete(connect, conn, app_db_url):
    lim = IpRateLimiter(connect)
    rule = IpLimitRule(MATCH_CREATE, 5, HOUR)
    lim.hit(rule, KEY_A)
    lim.hit(rule, KEY_B)
    conn.execute(
        "update public.ip_rate_limits set updated_at = now() - interval '25 hours'"
        " where ip_key = %s",
        (KEY_A,),
    )
    assert lim.purge() == 1
    assert lim.purge() == 0
    left = conn.execute("select ip_key from public.ip_rate_limits").fetchall()
    assert [bytes(r[0]) for r in left] == [KEY_B]
    with psycopg.connect(app_db_url) as app, pytest.raises(psycopg.errors.InsufficientPrivilege):
        app.execute("delete from public.ip_rate_limits")


def test_bad_rows_are_rejected(conn):
    with pytest.raises(psycopg.errors.CheckViolation):
        conn.execute(
            "insert into public.ip_rate_limits (scope, ip_key) values ('x', %s)", (b"short",)
        )
    with pytest.raises(psycopg.errors.CheckViolation):
        conn.execute(
            "insert into public.ip_rate_limits (scope, ip_key) values ('Bad-Scope', %s)", (KEY_A,)
        )


# -- routes ---------------------------------------------------------------------------------


def test_raw_ip_is_never_stored(connect, conn):
    c = make_client(connect, session_token_secret="s3cret", forwarded_hops=1)  # noqa: S106
    assert c.post(f"{API}/sessions", headers={"X-Forwarded-For": "198.51.100.7"}).status_code == 201
    (key,) = conn.execute("select ip_key from public.ip_rate_limits").fetchone()
    assert bytes(key) == tokens.ip_key("198.51.100.7", b"s3cret")
    dump = conn.execute("select row_to_json(r)::text from public.ip_rate_limits r").fetchone()[0]
    assert "198.51.100.7" not in dump and "testclient" not in dump


def test_assessment_is_limited_per_ip(connect):
    c = make_client(connect, ip_limit_assessment_requests=2)
    url = f"{API}/match-contexts/{uuid4()}/assessment"
    assert c.get(url).status_code == 404  # unknown matches are counted too
    assert c.get(url).status_code == 404
    res = c.get(url)
    assert res.status_code == 429
    assert res.json()["error"]["code"] == "RATE_LIMITED"
    assert res.json()["error"]["retry_at"] is not None
    assert 0 < int(res.headers["Retry-After"]) <= 600


def test_assessment_limit_works_without_a_session_secret(connect):
    """Without the session secret a per-process key hashes the IP; the limit still applies."""
    c = make_client(connect, ip_limit_assessment_requests=1)
    url = f"{API}/match-contexts/{uuid4()}/assessment"
    assert c.get(url).status_code == 404
    assert c.get(url).status_code == 429


def test_match_create_is_limited_and_invalid_input_is_not_counted(connect):
    c = make_client(connect, ip_limit_match_creates_per_hour=1)
    bad = {"kickoff_at": "2026-12-01T15:00:00", "venue": "rizal_memorial"}
    for _ in range(3):
        assert c.post(f"{API}/match-contexts", json=bad).status_code == 422
    assert c.post(f"{API}/match-contexts", json=MATCH_BODY).status_code == 201
    assert c.post(f"{API}/match-contexts", json=MATCH_BODY).status_code == 429


def test_refused_ingestion_requests_do_not_use_the_ip_budget(connect):
    """P-27 A5: a request that starts or reuses no job (here 409: no source groups) is not
    counted. Counted requests are tested in test_weather_api.py."""
    c = make_client(connect, ip_limit_ingestion_requests_per_hour=1)
    match_id = c.post(f"{API}/match-contexts", json=MATCH_BODY).json()["id"]
    url = f"{API}/match-contexts/{match_id}/ingestions"
    assert [c.post(url).status_code for _ in range(3)] == [409, 409, 409]


def test_separate_ips_get_separate_limits_behind_the_proxy(connect):
    c = make_client(connect, ip_limit_match_creates_per_hour=1, forwarded_hops=1)
    one = {"X-Forwarded-For": "203.0.113.1"}
    two = {"X-Forwarded-For": "203.0.113.2"}
    assert c.post(f"{API}/match-contexts", json=MATCH_BODY, headers=one).status_code == 201
    assert c.post(f"{API}/match-contexts", json=MATCH_BODY, headers=one).status_code == 429
    assert c.post(f"{API}/match-contexts", json=MATCH_BODY, headers=two).status_code == 201
