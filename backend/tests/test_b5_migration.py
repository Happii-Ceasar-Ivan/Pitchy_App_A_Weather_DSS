"""B5 migration: pgvector chunks, metadata-only conversation events, chat retention."""

from datetime import UTC, datetime, timedelta

import psycopg
import pytest
from psycopg import errors

from tests.conftest import requires_db

pytestmark = requires_db

PURGE = "select * from public.purge_old_conversation_data(%s)"


def _match(conn: psycopg.Connection) -> str:
    location = conn.execute(
        "insert into public.locations (name, latitude, longitude, scope_key)"
        " values ('B5 venue', 14.6, 121.0, 'b5-scope') returning id"
    ).fetchone()[0]
    return conn.execute(
        "insert into public.match_contexts (kickoff_at, location_id) values (now(), %s)"
        " returning id",
        (location,),
    ).fetchone()[0]


def _document(conn: psycopg.Connection, key: str = "fifa_ecm_2022") -> str:
    return conn.execute(
        "insert into public.protocol_documents (title, authority, version, document_key,"
        " approval_status) values (%s, 'FIFA', '2022', %s, 'approved') returning id",
        (f"Manual {key}", key),
    ).fetchone()[0]


def _vector(first: float) -> str:
    return "[" + ",".join([str(first)] + ["0"] * 767) + "]"


def _event(conn, match_id, *, generation="generated", provider="gemini", called=True, age=None):
    return conn.execute(
        "insert into public.conversation_events (match_context_id, role, generation,"
        " outcome_code, provider_called, provider, occurred_at)"
        " values (%s, 'coach', %s, 'GENERATED', %s, %s, %s) returning id",
        (match_id, generation, called, provider, datetime.now(UTC) - (age or timedelta())),
    ).fetchone()[0]


def test_chunks_store_768_dim_embeddings_and_full_text(conn) -> None:
    doc = _document(conn)
    conn.execute(
        "insert into public.protocol_chunks (document_id, position, section, content, embedding,"
        " embedding_model) values (%s, 0, 'Chapter 9', 'Cooling breaks at WBGT 32 degrees.',"
        " %s::extensions.vector, 'gemini-embedding-test')",
        (doc, _vector(1)),
    )
    near = conn.execute(
        "select section from public.protocol_chunks"
        " order by embedding operator(extensions.<=>) %s::extensions.vector limit 1",
        (_vector(0.5),),
    ).fetchone()
    assert near == ("Chapter 9",)
    hit = conn.execute(
        "select count(*) from public.protocol_chunks"
        " where fts @@ websearch_to_tsquery('english', 'cooling break')"
    ).fetchone()[0]
    assert hit == 1


def test_wrong_dimension_or_model_without_embedding_is_refused(conn) -> None:
    doc = _document(conn)
    with pytest.raises(errors.DataException):
        conn.execute(
            "insert into public.protocol_chunks (document_id, position, content, embedding,"
            " embedding_model) values (%s, 0, 'x', '[1,2,3]'::extensions.vector, 'm')",
            (doc,),
        )
    with pytest.raises(errors.CheckViolation):
        conn.execute(
            "insert into public.protocol_chunks (document_id, position, content, embedding_model)"
            " values (%s, 1, 'x', 'm')",
            (doc,),
        )


def test_document_key_is_unique_and_slug_shaped(conn) -> None:
    doc = _document(conn)
    with pytest.raises(errors.UniqueViolation):
        conn.execute(
            "insert into public.protocol_documents (title, authority, version, document_key)"
            " values ('Other title', 'FIFA', '2022', 'fifa_ecm_2022')"
        )
    assert doc
    with pytest.raises(errors.CheckViolation):
        _document(conn, "FIFA ECM")


def test_conversation_events_hold_metadata_only(conn) -> None:
    columns = {
        r[0]
        for r in conn.execute(
            "select column_name from information_schema.columns"
            " where table_schema = 'public' and table_name = 'conversation_events'"
        )
    }
    assert columns.isdisjoint({"session_id", "question", "answer", "ip", "ip_hash", "token_hash"})


def test_conversation_event_checks(conn) -> None:
    match_id = _match(conn)
    _event(conn, match_id)
    _event(conn, match_id, generation="unavailable", provider=None, called=False)
    with pytest.raises(errors.CheckViolation):  # generated needs the provider that answered
        _event(conn, match_id, provider=None)
    with pytest.raises(errors.CheckViolation):  # a provider answered, so one was called
        _event(conn, match_id, called=False)
    with pytest.raises(errors.CheckViolation):
        _event(conn, match_id, provider="nvidia")


def test_backend_role_reads_documents_but_cannot_write_them(app_db_url, conn) -> None:
    _document(conn)
    match_id = _match(conn)
    with psycopg.connect(app_db_url, autocommit=True) as app:
        assert app.execute("select count(*) from public.protocol_documents").fetchone()[0] == 1
        _event(app, match_id)
        with pytest.raises(errors.InsufficientPrivilege):
            app.execute("update public.protocol_documents set title = 'x'")
        with pytest.raises(errors.InsufficientPrivilege):
            app.execute("delete from public.conversation_events")


def test_purge_drops_old_events_and_idle_sessions_only(app_db_url, conn) -> None:
    match_id = _match(conn)
    old = _event(conn, match_id, age=timedelta(days=31))
    new = _event(conn, match_id, age=timedelta(days=29))
    month = datetime.now(UTC) - timedelta(days=31)
    idle, used, fresh = (
        conn.execute(
            "insert into public.anonymous_sessions (token_hash, created_at, last_request_at)"
            " values (%s, %s, %s) returning id",
            (bytes([i]) * 32, created, last),
        ).fetchone()[0]
        for i, (created, last) in enumerate(
            [(month, None), (month, datetime.now(UTC)), (datetime.now(UTC), None)], start=1
        )
    )
    with psycopg.connect(app_db_url, autocommit=True) as app:
        assert app.execute(PURGE, (timedelta(days=30),)).fetchone() == (1, 1)
    events = {r[0] for r in conn.execute("select id from public.conversation_events")}
    sessions = {r[0] for r in conn.execute("select id from public.anonymous_sessions")}
    assert old not in events and new in events
    assert idle not in sessions and {used, fresh} <= sessions


def test_purge_refuses_short_periods_and_clients(conn) -> None:
    with pytest.raises(errors.RaiseException):
        conn.execute(PURGE, (timedelta(hours=1),))
    for role in ("anon", "authenticated"):
        assert not conn.execute(
            "select has_function_privilege(%s,"
            " 'public.purge_old_conversation_data(interval)', 'execute')",
            (role,),
        ).fetchone()[0]
