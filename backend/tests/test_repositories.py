"""Repository tests, run as the least-privilege login (local PostgreSQL; see conftest.py)."""

import threading
from datetime import UTC, datetime, timedelta

import psycopg
import pytest

from shared.db.records import NewForecastValue
from shared.db.repositories import (
    PgAnonymousSessionRepository,
    PgForecastRepository,
    PgIngestionJobRepository,
    PgLocationRepository,
    PgMatchContextRepository,
    PgWeatherSourceRepository,
)
from tests.conftest import requires_db

pytestmark = requires_db
LEASE = timedelta(minutes=5)
KICKOFF = datetime(2026, 12, 1, 7, 0, tzinfo=UTC)


@pytest.fixture
def location(connect):
    return PgLocationRepository(connect).get_or_create("grid:14.60:121.00", 14.6, 121.0, "Venue")


def test_sources_seeded_and_none_enabled(connect) -> None:
    repo = PgWeatherSourceRepository(connect)
    assert repo.get("pagasa").name == "PAGASA"
    assert repo.get("unknown") is None
    assert repo.list_enabled() == []


def test_location_get_or_create_is_idempotent(connect, location) -> None:
    again = PgLocationRepository(connect).get_or_create(location.scope_key, 1.0, 2.0, "Other")
    assert again.id == location.id
    assert (again.latitude, again.longitude) == (14.6, 121.0)


def test_match_context_round_trip_keeps_utc(connect, location) -> None:
    repo = PgMatchContextRepository(connect)
    created = repo.create(KICKOFF, location.id, "Venue", None)
    fetched = repo.get(created.id)
    assert fetched == created
    assert fetched.kickoff_at == KICKOFF


def test_first_acquire_wins_and_second_gets_same_job(connect, location) -> None:
    repo = PgIngestionJobRepository(connect)
    first = repo.acquire("pagasa:grid", "pagasa", location.id, LEASE)
    second = repo.acquire("pagasa:grid", "pagasa", location.id, LEASE)
    assert first.acquired and not second.acquired
    assert second.job.id == first.job.id
    assert first.job.state == "running"


def test_many_simultaneous_acquires_one_winner(connect, location) -> None:
    repo = PgIngestionJobRepository(connect)
    results, barrier = [], threading.Barrier(5)

    def attempt() -> None:
        barrier.wait()
        results.append(repo.acquire("pagasa:grid", "pagasa", location.id, LEASE))

    threads = [threading.Thread(target=attempt) for _ in range(5)]
    for t in threads:
        t.start()
    for t in threads:
        t.join(timeout=20)

    assert len(results) == 5
    assert sum(r.acquired for r in results) == 1
    assert len({r.job.id for r in results}) == 1


def test_finish_releases_lock_for_retry(connect, location) -> None:
    repo = PgIngestionJobRepository(connect)
    failed = repo.acquire("pagasa:grid", "pagasa", location.id, LEASE).job
    assert repo.finish(failed.id, succeeded=False, failure_code="SOURCE_DOWN", failure_message="x")
    assert repo.get(failed.id).state == "failed"
    retry = repo.acquire("pagasa:grid", "pagasa", location.id, LEASE)
    assert retry.acquired and retry.job.id != failed.id


def test_expired_lease_is_taken_over_and_late_worker_cannot_finish(connect, location) -> None:
    repo = PgIngestionJobRepository(connect)
    abandoned = repo.acquire("pagasa:grid", "pagasa", location.id, timedelta(seconds=-1)).job
    takeover = repo.acquire("pagasa:grid", "pagasa", location.id, LEASE)
    assert takeover.acquired
    old = repo.get(abandoned.id)
    assert (old.state, old.failure_code) == ("expired", "LEASE_EXPIRED")
    assert not repo.finish(abandoned.id, succeeded=True)
    assert not repo.renew_lease(abandoned.id, LEASE)
    assert repo.renew_lease(takeover.job.id, LEASE)
    assert repo.finish(takeover.job.id, succeeded=True)


def test_unrelated_scopes_acquire_independently(connect, location) -> None:
    repo = PgIngestionJobRepository(connect)
    assert repo.acquire("pagasa:grid", "pagasa", location.id, LEASE).acquired
    assert repo.acquire("open_meteo:grid", "open_meteo", location.id, LEASE).acquired


def test_fetch_stores_values_with_db_retrieval_time(connect, location) -> None:
    repo = PgForecastRepository(connect)
    window = (KICKOFF - timedelta(hours=1), KICKOFF + timedelta(hours=2))
    before = datetime.now(UTC) - timedelta(minutes=1)
    repo.record_fetch(
        "pagasa",
        location.id,
        None,
        [
            NewForecastValue("p_a", 1.5, "u", "ok", *window, None),
            NewForecastValue("p_b", None, None, "missing", *window, None),
            NewForecastValue("p_c", 2.0, "u", "ok", KICKOFF + timedelta(hours=3),
                             KICKOFF + timedelta(hours=4), None),
        ],
    )  # fmt: skip
    covering = repo.values_covering(location.id, KICKOFF)
    assert {v.parameter for v in covering} == {"p_a", "p_b"}  # p_c doesn't cover kickoff
    assert all(v.retrieved_at >= before for v in covering)
    assert [v.parameter for v in repo.values_covering(location.id, KICKOFF, ["p_a"])] == ["p_a"]


def test_failed_fetch_is_recorded(connect, conn, location) -> None:
    fetch = PgForecastRepository(connect).record_failed_fetch(
        "pagasa", location.id, None, "TIMEOUT", "Source did not answer in time."
    )
    status = conn.execute("select status from public.source_fetches where id = %s", (fetch,))
    assert status.fetchone()[0] == "failed"


def test_session_create_and_lookup(connect) -> None:
    repo = PgAnonymousSessionRepository(connect)
    token_hash = bytes(range(32))
    created = repo.create(token_hash)
    assert created.counted_prompt_times == [] and created.cooldown_until is None
    assert repo.get_by_hash(token_hash).id == created.id
    with pytest.raises(psycopg.errors.UniqueViolation):
        repo.create(token_hash)
