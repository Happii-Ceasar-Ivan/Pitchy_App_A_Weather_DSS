"""Data-access interfaces (``Protocol``) and their PostgreSQL implementations (Sprint B1-5).

Rules for every query here:
- Parameterized SQL only; never build SQL from input strings (checklist: SQL injection).
- Timestamps that matter (retrieved_at, leases, job times) come from the database clock, never
  from the client or the app server.
- No freshness, validity or safety rules live here; this layer only stores and fetches facts.

Each repository takes a ``ConnectionFactory`` (``pool.connection`` in the app, a plain
``psycopg.connect`` in tests) and runs each method in its own transaction.
"""

from collections.abc import Sequence
from datetime import datetime, timedelta
from typing import Protocol
from uuid import UUID

from psycopg.rows import class_row, dict_row
from psycopg.types.json import Jsonb

from shared.db.pool import ConnectionFactory
from shared.db.records import (
    AlertCheckRecord,
    AnonymousSessionRecord,
    FetchAttempt,
    FetchCoverage,
    FetchFailureRecord,
    ForecastValueRecord,
    IngestionJobRecord,
    LightningCheckRecord,
    Location,
    LockResult,
    MatchContextRecord,
    NewForecastValue,
    StoredAlertRecord,
    WeatherSource,
)

# --- Interfaces ---------------------------------------------------------------------------------


class WeatherSourceRepository(Protocol):
    def get(self, source_id: str) -> WeatherSource | None: ...
    def list_enabled(self) -> list[WeatherSource]: ...


class LocationRepository(Protocol):
    def get_or_create(
        self, scope_key: str, latitude: float, longitude: float, name: str | None
    ) -> Location: ...
    def list_all(self) -> list[Location]: ...
    def get(self, location_id: UUID) -> Location | None: ...
    def get_by_scope_key(self, scope_key: str) -> Location | None: ...


class MatchContextRepository(Protocol):
    def create(
        self,
        kickoff_at: datetime,
        location_id: UUID,
        venue_name: str | None,
        pitch_surface: str | None,
        age_group: str = "senior",
    ) -> MatchContextRecord: ...
    def get(self, match_context_id: UUID) -> MatchContextRecord | None: ...


class IngestionJobRepository(Protocol):
    def acquire(
        self, scope_key: str, source_id: str, location_id: UUID | None, lease: timedelta
    ) -> LockResult: ...
    def renew_lease(self, job_id: UUID, lease: timedelta) -> bool: ...
    def finish(
        self,
        job_id: UUID,
        succeeded: bool,
        failure_code: str | None = None,
        failure_message: str | None = None,
    ) -> bool: ...
    def get(self, job_id: UUID) -> IngestionJobRecord | None: ...
    def active_for_scopes(self, scope_keys: Sequence[str]) -> list[IngestionJobRecord]: ...


class ForecastRepository(Protocol):
    def record_fetch(
        self,
        source_id: str,
        location_id: UUID,
        ingestion_job_id: UUID | None,
        values: Sequence[NewForecastValue],
        *,
        source_issued_at: datetime | None = None,
        raw_content_type: str | None = None,
        raw_payload: str | None = None,
        raw_payload_sha256: str | None = None,
    ) -> UUID: ...
    def record_failed_fetch(
        self,
        source_id: str,
        location_id: UUID,
        ingestion_job_id: UUID | None,
        error_code: str,
        error_summary: str,
    ) -> UUID: ...
    def values_covering(
        self, location_id: UUID, at: datetime, parameters: Sequence[str] | None = None
    ) -> list[ForecastValueRecord]: ...
    def last_gap_attempt(
        self, source_ids: Sequence[str], location_id: UUID, blocking_codes: Sequence[str]
    ) -> FetchAttempt | None: ...
    def recent_fetches(self, limit: int = 20) -> list[dict]: ...
    def recent_coverage(
        self, source_id: str, location_id: UUID, start: datetime, end: datetime, limit: int = 10
    ) -> list[FetchCoverage]: ...
    def latest_attempt(self, source_id: str, location_id: UUID) -> FetchAttempt | None: ...
    def failures_for_job(self, job_id: UUID) -> list[FetchFailureRecord]: ...


class AnonymousSessionRepository(Protocol):
    def create(self, token_hash: bytes) -> AnonymousSessionRecord: ...
    def get_by_hash(self, token_hash: bytes) -> AnonymousSessionRecord | None: ...


# --- PostgreSQL implementations -----------------------------------------------------------------


class _Repo:
    def __init__(self, connect: ConnectionFactory) -> None:
        self._connect = connect


class PgWeatherSourceRepository(_Repo):
    def get(self, source_id: str) -> WeatherSource | None:
        with self._connect() as conn:
            cur = conn.cursor(row_factory=class_row(WeatherSource))
            return cur.execute(
                "select * from public.weather_sources where id = %s", (source_id,)
            ).fetchone()

    def list_enabled(self) -> list[WeatherSource]:
        with self._connect() as conn:
            cur = conn.cursor(row_factory=class_row(WeatherSource))
            return cur.execute(
                "select * from public.weather_sources where enabled order by id"
            ).fetchall()


class PgLocationRepository(_Repo):
    def get_or_create(
        self, scope_key: str, latitude: float, longitude: float, name: str | None
    ) -> Location:
        with self._connect() as conn:
            cur = conn.cursor(row_factory=class_row(Location))
            # DO UPDATE with a no-op so RETURNING yields the existing row as well.
            return cur.execute(
                "insert into public.locations (scope_key, latitude, longitude, name)"
                " values (%s, %s, %s, %s)"
                " on conflict (scope_key) do update set scope_key = excluded.scope_key"
                " returning *",
                (scope_key, latitude, longitude, name),
            ).fetchone()

    def list_all(self) -> list[Location]:
        with self._connect() as conn:
            cur = conn.cursor(row_factory=class_row(Location))
            return cur.execute("select * from public.locations order by scope_key").fetchall()

    def get(self, location_id: UUID) -> Location | None:
        with self._connect() as conn:
            cur = conn.cursor(row_factory=class_row(Location))
            return cur.execute(
                "select * from public.locations where id = %s", (location_id,)
            ).fetchone()

    def get_by_scope_key(self, scope_key: str) -> Location | None:
        with self._connect() as conn:
            cur = conn.cursor(row_factory=class_row(Location))
            return cur.execute(
                "select * from public.locations where scope_key = %s", (scope_key,)
            ).fetchone()


class PgMatchContextRepository(_Repo):
    def create(
        self,
        kickoff_at: datetime,
        location_id: UUID,
        venue_name: str | None,
        pitch_surface: str | None,
        age_group: str = "senior",
    ) -> MatchContextRecord:
        with self._connect() as conn:
            cur = conn.cursor(row_factory=class_row(MatchContextRecord))
            return cur.execute(
                "insert into public.match_contexts"
                " (kickoff_at, location_id, venue_name, pitch_surface, age_group)"
                " values (%s, %s, %s, %s, %s) returning *",
                (kickoff_at, location_id, venue_name, pitch_surface, age_group),
            ).fetchone()

    def get(self, match_context_id: UUID) -> MatchContextRecord | None:
        with self._connect() as conn:
            cur = conn.cursor(row_factory=class_row(MatchContextRecord))
            return cur.execute(
                "select * from public.match_contexts where id = %s", (match_context_id,)
            ).fetchone()


class PgIngestionJobRepository(_Repo):
    """The shared ingestion lock (decision L1). See supabase/migrations for the index."""

    _ACQUIRE_ATTEMPTS = 3

    def acquire(
        self, scope_key: str, source_id: str, location_id: UUID | None, lease: timedelta
    ) -> LockResult:
        for _ in range(self._ACQUIRE_ATTEMPTS):
            with self._connect() as conn, conn.transaction():
                cur = conn.cursor(row_factory=class_row(IngestionJobRecord))
                # 1. Release an abandoned lock: an active job whose lease has run out.
                conn.execute(
                    "update public.ingestion_jobs set state = 'expired', finished_at = now(),"
                    " failure_code = 'LEASE_EXPIRED',"
                    " failure_message = 'The job stopped renewing its lease.'"
                    " where scope_key = %s and state in ('queued', 'running')"
                    " and lease_expires_at <= now()",
                    (scope_key,),
                )
                # 2. Try to take the lock. A concurrent winner makes this a no-op.
                job = cur.execute(
                    "insert into public.ingestion_jobs"
                    " (scope_key, source_id, location_id, state, started_at, lease_expires_at)"
                    " values (%s, %s, %s, 'running', now(), now() + %s)"
                    " on conflict (scope_key) where state in ('queued', 'running') do nothing"
                    " returning *",
                    (scope_key, source_id, location_id, lease),
                ).fetchone()
                if job is not None:
                    return LockResult(job=job, acquired=True)
                # 3. Someone else holds it: hand back their job so the client can poll it.
                existing = cur.execute(
                    "select * from public.ingestion_jobs"
                    " where scope_key = %s and state in ('queued', 'running')",
                    (scope_key,),
                ).fetchone()
                if existing is not None:
                    return LockResult(job=existing, acquired=False)
            # The holder finished between steps 2 and 3; try again.
        raise RuntimeError(f"Could not acquire or observe the ingestion lock for {scope_key!r}")

    def renew_lease(self, job_id: UUID, lease: timedelta) -> bool:
        """Extend a running job's lease. False if it already expired or finished."""
        with self._connect() as conn:
            row = conn.execute(
                "update public.ingestion_jobs set lease_expires_at = now() + %s"
                " where id = %s and state = 'running' and lease_expires_at > now()"
                " returning id",
                (lease, job_id),
            ).fetchone()
            return row is not None

    def finish(
        self,
        job_id: UUID,
        succeeded: bool,
        failure_code: str | None = None,
        failure_message: str | None = None,
    ) -> bool:
        """Mark a job finished and release the lock.

        Returns False if this worker no longer owns the job (it expired and may have been
        taken over), so a late worker can never overwrite a newer job's outcome.
        """
        state = "succeeded" if succeeded else "failed"
        with self._connect() as conn:
            row = conn.execute(
                "update public.ingestion_jobs set state = %s, finished_at = now(),"
                " failure_code = %s, failure_message = %s"
                " where id = %s and state = 'running' and lease_expires_at > now()"
                " returning id",
                (state, None if succeeded else failure_code,
                 None if succeeded else failure_message, job_id),
            ).fetchone()  # fmt: skip
            return row is not None

    def get(self, job_id: UUID) -> IngestionJobRecord | None:
        with self._connect() as conn:
            cur = conn.cursor(row_factory=class_row(IngestionJobRecord))
            return cur.execute(
                "select * from public.ingestion_jobs where id = %s", (job_id,)
            ).fetchone()

    def active_for_scopes(self, scope_keys: Sequence[str]) -> list[IngestionJobRecord]:
        """Jobs holding a lock right now. A job whose lease ran out is not active."""
        with self._connect() as conn:
            cur = conn.cursor(row_factory=class_row(IngestionJobRecord))
            return cur.execute(
                "select * from public.ingestion_jobs where scope_key = any(%s)"
                " and state in ('queued', 'running') and lease_expires_at > now()"
                " order by scope_key",
                (list(scope_keys),),
            ).fetchall()


class PgForecastRepository(_Repo):
    def record_fetch(
        self,
        source_id: str,
        location_id: UUID,
        ingestion_job_id: UUID | None,
        values: Sequence[NewForecastValue],
        *,
        source_issued_at: datetime | None = None,
        raw_content_type: str | None = None,
        raw_payload: str | None = None,
        raw_payload_sha256: str | None = None,
    ) -> UUID:
        """Store one successful source call and its values atomically; retrieved_at = now()."""
        with self._connect() as conn, conn.transaction():
            fetch_id, retrieved_at = conn.execute(
                "insert into public.source_fetches (source_id, location_id, ingestion_job_id,"
                " completed_at, status, source_issued_at, raw_content_type, raw_payload,"
                " raw_payload_sha256)"
                " values (%s, %s, %s, now(), 'succeeded', %s, %s, %s, %s)"
                " returning id, completed_at",
                (source_id, location_id, ingestion_job_id, source_issued_at,
                 raw_content_type, raw_payload, raw_payload_sha256),
            ).fetchone()  # fmt: skip
            # One statement for every value: column arrays expanded with unnest(), so the whole
            # fetch is a single round trip. (COPY is faster still but is refused under RLS for
            # non-owner roles such as pitchy_app.)
            conn.execute(
                "insert into public.forecast_values (fetch_id, source_id, location_id,"
                " parameter, value, unit, value_state, retrieved_at, forecast_valid_from,"
                " forecast_valid_until, expires_at)"
                " select %s, %s, %s, x.p, x.v, x.u, x.s, %s, x.f, x.t, x.e"
                " from unnest(%s::text[], %s::float8[], %s::text[], %s::text[],"
                "             %s::timestamptz[], %s::timestamptz[], %s::timestamptz[])"
                "      as x(p, v, u, s, f, t, e)",
                (fetch_id, source_id, location_id, retrieved_at,
                 [v.parameter for v in values], [v.value for v in values],
                 [v.unit for v in values], [v.value_state for v in values],
                 [v.forecast_valid_from for v in values],
                 [v.forecast_valid_until for v in values], [v.expires_at for v in values]),
            )  # fmt: skip
            return fetch_id

    def record_failed_fetch(
        self,
        source_id: str,
        location_id: UUID,
        ingestion_job_id: UUID | None,
        error_code: str,
        error_summary: str,
    ) -> UUID:
        with self._connect() as conn:
            return conn.execute(
                "insert into public.source_fetches (source_id, location_id, ingestion_job_id,"
                " completed_at, status, error_code, error_summary)"
                " values (%s, %s, %s, now(), 'failed', %s, %s) returning id",
                (source_id, location_id, ingestion_job_id, error_code, error_summary),
            ).fetchone()[0]

    def values_covering(
        self, location_id: UUID, at: datetime, parameters: Sequence[str] | None = None
    ) -> list[ForecastValueRecord]:
        """Values whose validity window includes ``at``, newest retrieval first.

        Coverage only: whether a value is fresh enough is decided by the cache service once
        DEC-04 sets the rules. Values with an unknown validity window are not returned.
        """
        with self._connect() as conn:
            cur = conn.cursor(row_factory=class_row(ForecastValueRecord))
            return cur.execute(
                "select * from public.forecast_values"
                " where location_id = %s and forecast_valid_from <= %s"
                " and forecast_valid_until > %s"
                " and (%s::text[] is null or parameter = any(%s::text[]))"
                " order by retrieved_at desc, source_id, parameter",
                (location_id, at, at, parameters, parameters),
            ).fetchall()

    def values_between(
        self, location_id: UUID, start: datetime, end: datetime, source_id: str
    ) -> list[ForecastValueRecord]:
        """Values from the latest successful fetch of one source, valid within [start, end)."""
        with self._connect() as conn:
            cur = conn.cursor(row_factory=class_row(ForecastValueRecord))
            return cur.execute(
                "select v.* from public.forecast_values v"
                " where v.fetch_id = (select f.id from public.source_fetches f"
                "   where f.source_id = %s and f.location_id = %s and f.status = 'succeeded'"
                "   order by f.requested_at desc limit 1)"
                " and v.forecast_valid_until > %s and v.forecast_valid_from < %s"
                " order by v.parameter, v.forecast_valid_from",
                (source_id, location_id, start, end),
            ).fetchall()

    def last_gap_attempt(
        self, source_ids: Sequence[str], location_id: UUID, blocking_codes: Sequence[str]
    ) -> FetchAttempt | None:
        """The newest call to any of these sources for a location that starts a minimum gap
        (FR-WTH-008 as refined by P-27): a success, or a failure whose code is in
        ``blocking_codes`` (the source refused us). Ordinary failures are not returned."""
        with self._connect() as conn:
            cur = conn.cursor(row_factory=class_row(FetchAttempt))
            return cur.execute(
                "select id, status, requested_at, error_code, error_summary"
                " from public.source_fetches where source_id = any(%s) and location_id = %s"
                " and (status = 'succeeded' or error_code = any(%s))"
                " order by requested_at desc limit 1",
                (list(source_ids), location_id, list(blocking_codes)),
            ).fetchone()

    def recent_fetches(self, limit: int = 20) -> list[dict]:
        """Latest source calls with counts, for status views. No raw payloads."""
        with self._connect() as conn:
            cur = conn.cursor(row_factory=dict_row)
            return cur.execute(
                "select f.id, f.source_id, l.scope_key as venue, f.status, f.error_code,"
                " f.error_summary, f.requested_at, f.completed_at, f.source_issued_at,"
                " (select count(*) from public.forecast_values v where v.fetch_id = f.id)"
                " as value_count"
                " from public.source_fetches f join public.locations l on l.id = f.location_id"
                " order by f.requested_at desc limit %s",
                (limit,),
            ).fetchall()

    def recent_coverage(
        self, source_id: str, location_id: UUID, start: datetime, end: datetime, limit: int = 10
    ) -> list[FetchCoverage]:
        """The latest successful fetches (newest first), each with the distinct validity
        windows of its usable ('ok') values that overlap [start, end)."""
        with self._connect() as conn:
            rows = conn.execute(
                "with recent as (select id, completed_at, source_issued_at, requested_at"
                "   from public.source_fetches"
                "   where source_id = %s and location_id = %s and status = 'succeeded'"
                "   order by requested_at desc limit %s)"
                " select r.id, r.completed_at, r.source_issued_at, w.f, w.t from recent r"
                " left join lateral (select distinct v.forecast_valid_from f,"
                "   v.forecast_valid_until t from public.forecast_values v"
                "   where v.fetch_id = r.id and v.value_state = 'ok'"
                "   and v.forecast_valid_until > %s and v.forecast_valid_from < %s) w on true"
                " order by r.requested_at desc, w.f, w.t",
                (source_id, location_id, limit, start, end),
            ).fetchall()
        result: list[FetchCoverage] = []
        for fetch_id, retrieved_at, issued_at, valid_from, valid_until in rows:
            if not result or result[-1].fetch_id != fetch_id:
                result.append(FetchCoverage(fetch_id, retrieved_at, issued_at, ()))
            if valid_from is not None:
                last = result[-1]
                result[-1] = FetchCoverage(
                    last.fetch_id, last.retrieved_at, last.source_issued_at,
                    (*last.windows, (valid_from, valid_until)),
                )  # fmt: skip
        return result

    def latest_attempt(self, source_id: str, location_id: UUID) -> FetchAttempt | None:
        with self._connect() as conn:
            cur = conn.cursor(row_factory=class_row(FetchAttempt))
            return cur.execute(
                "select id, status, requested_at, error_code, error_summary"
                " from public.source_fetches where source_id = %s and location_id = %s"
                " order by requested_at desc limit 1",
                (source_id, location_id),
            ).fetchone()

    def values_of_fetch(
        self, fetch_id: UUID, start: datetime, end: datetime
    ) -> list[ForecastValueRecord]:
        """Every value of one fetch whose validity window overlaps [start, end)."""
        with self._connect() as conn:
            cur = conn.cursor(row_factory=class_row(ForecastValueRecord))
            return cur.execute(
                "select * from public.forecast_values where fetch_id = %s"
                " and forecast_valid_until > %s and forecast_valid_from < %s"
                " order by parameter, forecast_valid_from",
                (fetch_id, start, end),
            ).fetchall()

    def failures_for_job(self, job_id: UUID) -> list[FetchFailureRecord]:
        with self._connect() as conn:
            cur = conn.cursor(row_factory=class_row(FetchFailureRecord))
            return cur.execute(
                "select source_id, error_code, error_summary from public.source_fetches"
                " where ingestion_job_id = %s and status = 'failed' order by source_id",
                (job_id,),
            ).fetchall()


class PgAlertRepository(_Repo):
    """Nationwide official alert checks (FR-SAF-007). Text is plain text from the parser."""

    def last_check(self) -> AlertCheckRecord | None:
        with self._connect() as conn:
            cur = conn.cursor(row_factory=class_row(AlertCheckRecord))
            return cur.execute(
                "select * from public.alert_checks order by checked_at desc limit 1"
            ).fetchone()

    def last_successful_check(self) -> AlertCheckRecord | None:
        with self._connect() as conn:
            cur = conn.cursor(row_factory=class_row(AlertCheckRecord))
            return cur.execute(
                "select * from public.alert_checks where status = 'succeeded'"
                " order by checked_at desc limit 1"
            ).fetchone()

    def record_check(
        self, job_id: UUID | None, alerts: Sequence[dict], active_cyclones: int
    ) -> UUID:
        """Store one successful check and all alerts it returned, atomically.

        Each alert dict has the ``official_alerts`` columns (identifier .. matched_venues)."""
        with self._connect() as conn, conn.transaction():
            check_id = conn.execute(
                "insert into public.alert_checks (ingestion_job_id, status, active_cyclones,"
                " alert_count) values (%s, 'succeeded', %s, %s) returning id",
                (job_id, active_cyclones, len(alerts)),
            ).fetchone()[0]
            for a in alerts:
                conn.execute(
                    "insert into public.official_alerts (check_id, identifier, issuer, event,"
                    " subtype, headline, message, issued_at, valid_until, areas,"
                    " matched_venues) values (%s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s)",
                    (check_id, a["identifier"], a["issuer"], a["event"], a["subtype"],
                     a["headline"], a["message"], a["issued_at"], a["valid_until"],
                     Jsonb(a["areas"]), list(a["matched_venues"])),
                )  # fmt: skip
            return check_id

    def record_failed_check(self, job_id: UUID | None, error_code: str, summary: str) -> UUID:
        with self._connect() as conn:
            return conn.execute(
                "insert into public.alert_checks (ingestion_job_id, status, error_code,"
                " error_summary) values (%s, 'failed', %s, %s) returning id",
                (job_id, error_code, summary),
            ).fetchone()[0]

    def alerts_of_check(self, check_id: UUID) -> list[StoredAlertRecord]:
        with self._connect() as conn:
            cur = conn.cursor(row_factory=class_row(StoredAlertRecord))
            return cur.execute(
                "select * from public.official_alerts where check_id = %s"
                " order by issued_at desc nulls last, identifier",
                (check_id,),
            ).fetchall()


class PgLightningRepository(_Repo):
    """Live lightning checks per venue (DEC-06). Flashes as returned, plus computed distance."""

    def last_check(self, location_id: UUID) -> LightningCheckRecord | None:
        with self._connect() as conn:
            cur = conn.cursor(row_factory=class_row(LightningCheckRecord))
            return cur.execute(
                "select * from public.lightning_checks where location_id = %s"
                " order by checked_at desc limit 1",
                (location_id,),
            ).fetchone()

    def last_successful_check(self, location_id: UUID) -> LightningCheckRecord | None:
        with self._connect() as conn:
            cur = conn.cursor(row_factory=class_row(LightningCheckRecord))
            return cur.execute(
                "select * from public.lightning_checks where location_id = %s"
                " and status = 'succeeded' order by checked_at desc limit 1",
                (location_id,),
            ).fetchone()

    def record_check(self, location_id: UUID, job_id: UUID | None, reading) -> UUID:
        flashes = [
            {"detected_at": f.detected_at.isoformat(), "latitude": f.latitude,
             "longitude": f.longitude, "distance_km": f.distance_km}
            for f in reading.flashes
        ]  # fmt: skip
        with self._connect() as conn:
            return conn.execute(
                "insert into public.lightning_checks (location_id, ingestion_job_id, status,"
                " radius_km, flash_count, nearest_km, latest_flash_at, flashes, raw_payload,"
                " raw_payload_sha256) values (%s, %s, 'succeeded', %s, %s, %s, %s, %s, %s, %s)"
                " returning id",
                (location_id, job_id, reading.radius_km, len(reading.flashes),
                 reading.nearest_km, reading.latest_at, Jsonb(flashes), reading.raw_payload,
                 reading.raw_payload_sha256),
            ).fetchone()[0]  # fmt: skip

    def record_failed_check(
        self, location_id: UUID, job_id: UUID | None, error_code: str, summary: str
    ) -> UUID:
        with self._connect() as conn:
            return conn.execute(
                "insert into public.lightning_checks (location_id, ingestion_job_id, status,"
                " error_code, error_summary) values (%s, %s, 'failed', %s, %s) returning id",
                (location_id, job_id, error_code, summary),
            ).fetchone()[0]


class PgAssessmentRepository(_Repo):
    """Saved safety assessments (FR-SAF-005, DEC-14: a new row only when the result changes)."""

    def latest(self, match_context_id: UUID) -> dict | None:
        with self._connect() as conn:
            cur = conn.cursor(row_factory=dict_row)
            return cur.execute(
                "select id, assessed_at, result->>'input_fingerprint' as fingerprint"
                " from public.safety_assessments where match_context_id = %s"
                " order by assessed_at desc limit 1",
                (match_context_id,),
            ).fetchone()

    def save(
        self,
        match_context_id: UUID,
        rule_version: str,
        result: dict,
        limitations: list,
        inputs: Sequence[tuple[int, str]],
    ) -> dict:
        """Store the result and the exact forecast values it used (hazard per value)."""
        with self._connect() as conn, conn.transaction():
            cur = conn.cursor(row_factory=dict_row)
            row = cur.execute(
                "insert into public.safety_assessments (match_context_id, rule_version, result,"
                " limitations) values (%s, %s, %s, %s) returning id, assessed_at",
                (match_context_id, rule_version, Jsonb(result), Jsonb(limitations)),
            ).fetchone()
            if inputs:
                conn.execute(
                    "insert into public.assessment_inputs"
                    " (assessment_id, forecast_value_id, hazard)"
                    " select %s, x.v, x.h from unnest(%s::bigint[], %s::text[]) as x(v, h)"
                    " on conflict do nothing",
                    (row["id"], [i for i, _ in inputs], [h for _, h in inputs]),
                )
            return row


class PgRetentionRepository(_Repo):
    """DEC-11 rotation through ``public.purge_old_weather_data`` (the backend role has no
    DELETE privilege of its own). Returns how many rows of each kind were deleted."""

    def purge(self, keep_forecasts: timedelta, keep_jobs: timedelta) -> dict[str, int]:
        with self._connect() as conn:
            cur = conn.cursor(row_factory=dict_row)
            return cur.execute(
                "select * from public.purge_old_weather_data(%s, %s)",
                (keep_forecasts, keep_jobs),
            ).fetchone()

    def purge_matches(self, keep: timedelta) -> dict[str, int]:
        """Matches whose kickoff is older than ``keep``, with their assessments and chat events
        (``public.purge_old_match_contexts``, B6)."""
        with self._connect() as conn:
            cur = conn.cursor(row_factory=dict_row)
            return cur.execute(
                "select * from public.purge_old_match_contexts(%s)", (keep,)
            ).fetchone()


class PgAnonymousSessionRepository(_Repo):
    """Storage only. The sliding-window/cooldown check is done atomically in Sprint B6."""

    def create(self, token_hash: bytes) -> AnonymousSessionRecord:
        with self._connect() as conn:
            cur = conn.cursor(row_factory=class_row(AnonymousSessionRecord))
            return cur.execute(
                "insert into public.anonymous_sessions (token_hash) values (%s) returning *",
                (token_hash,),
            ).fetchone()

    def get_by_hash(self, token_hash: bytes) -> AnonymousSessionRecord | None:
        with self._connect() as conn:
            cur = conn.cursor(row_factory=class_row(AnonymousSessionRecord))
            return cur.execute(
                "select * from public.anonymous_sessions where token_hash = %s", (token_hash,)
            ).fetchone()
