"""POST /match-contexts/{id}/conversation end to end (local PostgreSQL, fake AI providers).

No real AI or network call: providers are fakes, the embedder is a fake or None, lightning is a
quiet sky. The B4 assessment and the hybrid retrieval run for real.
"""

import json
import logging
from datetime import timedelta

import psycopg
import pytest
from fastapi.testclient import TestClient

from api.app import API_V1_PREFIX, create_app
from api.deps import (
    get_adapter_groups,
    get_ai_generators,
    get_connect,
    get_embedder,
    get_lightning_fetcher,
)
from services.ai_providers.base import EMBEDDING_DIMENSIONS, Generation, ProviderError
from services.weather_ingestion import registry
from shared.settings import Settings
from tests.conftest import requires_db
from tests.test_assessment_api import KICKOFF, quiet_sky, store

pytestmark = requires_db

API = API_V1_PREFIX
SECRET = "test-secret-" + "x" * 32


class FakeGenerator:
    """Replies in order; a ProviderError instance in the list is raised instead."""

    def __init__(self, name, replies, configured=True):
        self.name = name
        self._replies = list(replies)
        self._configured = configured
        self.calls = 0

    @property
    def configured(self):
        return self._configured

    def generate(self, system, prompt, *, timeout_s):
        self.calls += 1
        reply = self._replies.pop(0)
        if isinstance(reply, Exception):
            raise reply
        return Generation(self.name, "fake-model", reply)


class FakeEmbedder:
    model = "fake-embed"

    def __init__(self, fail=False):
        self.fail = fail

    def embed(self, texts, *, task):
        if self.fail:
            raise ProviderError("TIMEOUT")
        return [[1.0] + [0.0] * (EMBEDDING_DIMENSIONS - 1) for _ in texts]


def answer(text, sources=("A",)):
    return json.dumps({"answer": text, "sources": list(sources)})


GOOD = answer("The match management team decides on cooling breaks [A][D1].", ["A", "D1"])
QUESTION = {"role": "coach", "question": "Do we need cooling breaks today?"}


@pytest.fixture
def ai():
    """Mutable holder: tests set ai["generators"] and ai["embedder"] before calling."""
    return {"generators": [FakeGenerator("gemini", [GOOD])], "embedder": FakeEmbedder()}


@pytest.fixture
def client(connect, ai):
    app = create_app(Settings(env="test", session_token_secret=SECRET))
    app.dependency_overrides[get_connect] = lambda: connect
    app.dependency_overrides[get_adapter_groups] = lambda: registry.adapter_groups(Settings())
    app.dependency_overrides[get_lightning_fetcher] = lambda: quiet_sky
    app.dependency_overrides[get_ai_generators] = lambda: ai["generators"]
    app.dependency_overrides[get_embedder] = lambda: ai["embedder"]
    with TestClient(app) as c:
        yield c


@pytest.fixture
def document(conn):
    doc = conn.execute(
        "insert into public.protocol_documents (title, authority, version, document_key,"
        " approval_status) values ('FIFA Emergency Care Manual', 'FIFA', '2022',"
        " 'fifa_ecm_2022', 'approved') returning id"
    ).fetchone()[0]
    vector = "[" + ",".join(["1"] + ["0"] * (EMBEDDING_DIMENSIONS - 1)) + "]"
    conn.execute(
        "insert into public.protocol_chunks (document_id, position, section, content, embedding,"
        " embedding_model) values (%s, 0, 'Chapter 9', 'FIFA cooling breaks are decided by the"
        " match management team.', %s::extensions.vector, 'fake-embed')",
        (doc, vector),
    )


@pytest.fixture
def match_id(client, connect):
    store(connect)
    body = {"kickoff_at": KICKOFF.isoformat(), "venue": "rizal_memorial"}
    return client.post(f"{API}/match-contexts", json=body).json()["id"]


@pytest.fixture
def token(client):
    return client.post(f"{API}/sessions").json()["token"]


def ask(client, match_id, token, body=QUESTION):
    headers = {"X-Session-Token": token} if token else {}
    return client.post(f"{API}/match-contexts/{match_id}/conversation", json=body, headers=headers)


def events(conn):
    return conn.execute(
        "select outcome_code, generation, provider, provider_called, retrieval_mode,"
        " reference_keys from public.conversation_events order by occurred_at"
    ).fetchall()


def counted(conn):
    return conn.execute(
        "select coalesce(array_length(counted_prompt_times, 1), 0) from public.anonymous_sessions"
    ).fetchone()[0]


def codes(res):
    return [lim["code"] for lim in res.json()["limitations"]]


def ai_slots(conn):
    """Daily AI slots reserved today (B6 item 6)."""
    row = conn.execute("select coalesce(sum(reserved), 0) from public.chat_daily_ai_usage")
    return row.fetchone()[0]


def test_generated_answer_with_backend_references(client, conn, match_id, token, document):
    res = ask(client, match_id, token)
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["generation"] == "generated" and "[A][D1]" in body["answer"]
    assert body["assessment_id"] is not None
    assert codes(res)[0] == "AGENT_NOT_AUTHORITY"
    assert "fifa_ecm_2022" in {r["document_id"] for r in body["references"]}
    [row] = events(conn)
    assert row[:5] == ("GENERATED", "generated", "gemini", True, "hybrid")
    assert "fifa_ecm_2022" in row[5]  # [A] cites the assessment's own rule sources too
    assert counted(conn) == 1
    assert ai_slots(conn) == 1


def test_off_topic_question_never_reaches_the_ai(client, conn, ai, match_id, token):
    res = ask(client, match_id, token, {"role": "coach", "question": "Write me a poem about cats"})
    body = res.json()
    assert (body["generation"], body["answer"], body["assessment_id"]) == (
        "unavailable",
        None,
        None,
    )
    assert codes(res) == ["AGENT_NOT_AUTHORITY", "OFF_TOPIC"]
    assert ai["generators"][0].calls == 0
    assert events(conn)[0][:4] == ("OFF_TOPIC", "unavailable", None, False)
    assert ai_slots(conn) == 0  # no provider called: the daily slot was given back


def test_model_off_topic_flag_gives_the_fixed_decline(client, conn, ai, match_id, token):
    flag = json.dumps({"answer": "", "sources": [], "off_topic": True})
    ai["generators"] = [FakeGenerator("gemini", [flag])]
    question = {"role": "spectator", "question": "Who will win the match tonight?"}
    res = ask(client, match_id, token, question)
    assert res.json()["answer"] is None and codes(res)[-1] == "OFF_TOPIC"
    assert events(conn)[0][:4] == ("OFF_TOPIC", "unavailable", None, True)
    assert ai_slots(conn) == 1  # the provider was called, so the slot stays used


def test_uncited_answer_is_rejected_then_next_provider(client, conn, ai, match_id, token, document):
    poem = answer("Roses are red, the pitch is green.", [])
    ai["generators"] = [FakeGenerator("gemini", [poem]), FakeGenerator("groq", [GOOD])]
    res = ask(client, match_id, token)
    assert res.json()["generation"] == "generated"
    assert events(conn)[0][2] == "groq"


def test_missing_or_forged_token_is_401_and_not_counted(client, conn, match_id, token):
    assert ask(client, match_id, None).status_code == 401
    forged = token[:-2] + ("AA" if not token.endswith("AA") else "BB")
    res = ask(client, match_id, forged)
    assert res.status_code == 401 and res.json()["error"]["code"] == "INVALID_SESSION"
    assert counted(conn) == 0 and events(conn) == []


def test_eleventh_question_is_rate_limited(client, conn, ai, match_id, token, document):
    ai["generators"] = [FakeGenerator("gemini", [GOOD] * 10)]
    for _ in range(10):
        assert ask(client, match_id, token).status_code == 200
    res = ask(client, match_id, token)
    assert res.status_code == 429 and res.json()["error"]["retry_at"]
    assert "Retry-After" in res.headers
    assert len(events(conn)) == 10


# -- B5 WP7: end-to-end outcomes, privacy and retention ---------------------------------------


def invented(text="Expect 35 \u00b0C at kickoff [A]."):
    return answer(text, ["A"])


def test_every_provider_failing_is_unavailable_and_counted(client, conn, ai, match_id, token):
    ai["generators"] = [
        FakeGenerator("gemini", [ProviderError("TIMEOUT")]),
        FakeGenerator("groq", [ProviderError("RATE_LIMITED")]),
    ]
    res = ask(client, match_id, token)
    body = res.json()
    assert res.status_code == 200
    assert (body["generation"], body["answer"]) == ("unavailable", None)
    assert body["assessment_id"] is not None
    assert "AI_UNAVAILABLE" in codes(res)
    assert counted(conn) == 1
    [row] = events(conn)
    assert row[:4] == ("AI_UNAVAILABLE", "unavailable", None, True)


def test_every_reply_failing_the_answer_check_is_rejected_and_counted(
    client, conn, ai, match_id, token
):
    ai["generators"] = [
        FakeGenerator("gemini", [invented()]),
        FakeGenerator("groq", [invented()]),
    ]
    res = ask(client, match_id, token)
    body = res.json()
    assert (body["generation"], body["answer"]) == ("unavailable", None)
    assert "ANSWER_CHECK_FAILED" in codes(res)
    assert counted(conn) == 1
    assert events(conn)[0][:4] == ("ANSWER_CHECK_FAILED", "unavailable", None, True)


def test_no_provider_configured_is_not_counted_and_never_calls(client, conn, ai, match_id, token):
    gen = FakeGenerator("gemini", [GOOD], configured=False)
    ai["generators"] = [gen]
    res = ask(client, match_id, token)
    body = res.json()
    assert res.status_code == 200
    assert (body["generation"], body["answer"]) == ("unavailable", None)
    assert body["assessment_id"] is not None
    assert "AI_UNAVAILABLE" in codes(res)
    assert gen.calls == 0 and counted(conn) == 0
    assert events(conn)[0][:4] == ("AI_UNAVAILABLE", "unavailable", None, False)


def _fill_daily_cap(conn, days_ago=0):
    conn.execute(
        "insert into public.conversation_events (occurred_at, match_context_id, role, generation,"
        " outcome_code, provider_called, provider)"
        " select now() - make_interval(days => %s),"
        " (select id from public.match_contexts limit 1), 'coach',"
        " 'generated', 'GENERATED', true, 'gemini' from generate_series(1, 500)",
        (days_ago,),
    )


def test_daily_cap_reached_is_not_counted_and_never_calls(client, conn, ai, match_id, token):
    _fill_daily_cap(conn)
    gen = ai["generators"][0]
    res = ask(client, match_id, token)
    body = res.json()
    assert (body["generation"], body["answer"]) == ("unavailable", None)
    assert "DAILY_LIMIT_REACHED" in codes(res)
    assert gen.calls == 0 and counted(conn) == 0
    last = conn.execute(
        "select outcome_code, provider_called from public.conversation_events"
        " order by occurred_at desc limit 1"
    ).fetchone()
    assert last == ("DAILY_LIMIT_REACHED", False)


def test_events_from_before_today_do_not_count_toward_the_daily_cap(
    client, conn, ai, match_id, token, document
):
    _fill_daily_cap(conn, days_ago=2)
    res = ask(client, match_id, token)
    assert res.json()["generation"] == "generated"
    assert counted(conn) == 1


@pytest.mark.parametrize("embedder", [None, FakeEmbedder(fail=True)], ids=["none", "raises"])
def test_embedder_missing_or_failing_falls_back_to_keywords(
    client, conn, ai, match_id, token, document, embedder
):
    ai["embedder"] = embedder
    question = {"role": "coach", "question": "Who decides FIFA cooling breaks, the match team?"}
    res = ask(client, match_id, token, question)
    assert res.json()["generation"] == "generated"
    assert "RETRIEVAL_KEYWORD_ONLY" in codes(res)
    assert events(conn)[0][4] == "keyword_only"


def test_unknown_match_is_404_not_counted_no_event(client, conn, token):
    res = ask(client, "00000000-0000-4000-8000-000000000000", token)
    assert res.status_code == 404
    assert counted(conn) == 0 and events(conn) == []


@pytest.mark.parametrize(
    "body",
    [
        {"role": "janitor", "question": "Is it safe to play?"},
        {"role": "coach", "question": ""},
        {"role": "coach", "question": "x" * 2001},
    ],
    ids=["unknown_role", "empty_question", "too_long"],
)
def test_invalid_bodies_are_422_not_counted_no_event(client, conn, ai, match_id, token, body):
    res = ask(client, match_id, token, body)
    assert res.status_code == 422
    assert counted(conn) == 0 and events(conn) == []
    assert ai["generators"][0].calls == 0


def test_database_unreachable_is_503(client, match_id, token):
    def broken():
        raise psycopg.OperationalError("connection refused")

    client.app.dependency_overrides[get_connect] = lambda: broken
    res = ask(client, match_id, token)
    assert res.status_code == 503
    assert res.json()["error"]["code"] == "SERVICE_UNAVAILABLE"


def test_reply_citing_a_missing_block_is_rejected_and_references_are_backend_built(
    client, conn, ai, match_id, token, document
):
    ai["generators"] = [
        FakeGenerator("gemini", [answer("Cooling breaks are decided by officials [D7].", ["D7"])]),
        FakeGenerator("groq", [GOOD]),
    ]
    res = ask(client, match_id, token)
    body = res.json()
    assert body["generation"] == "generated" and "[D7]" not in body["answer"]
    assert events(conn)[0][2] == "groq"
    [row] = events(conn)
    allowed = set(row[5]) | {"fifa_ecm_2022"}
    refs = {r["document_id"] for r in body["references"]}
    assert refs and refs <= allowed
    assert "D7" not in json.dumps(body["references"])


def test_html_and_links_in_a_reply_are_stripped(client, ai, match_id, token, document):
    dirty = answer(
        "The <b>team</b> decides [A][D1]. See [the guide](https://evil.example/x)"
        " or https://evil.example/y now.",
        ["A", "D1"],
    )
    ai["generators"] = [FakeGenerator("gemini", [dirty])]
    res = ask(client, match_id, token)
    text = res.json()["answer"]
    assert res.json()["generation"] == "generated"
    for bad in ("<b>", "</b>", "](", "http", "evil.example"):
        assert bad not in text


def test_no_question_or_token_is_stored_or_logged(client, conn, match_id, token, document, caplog):
    secret_question = "Do we need cooling breaks zebra-umbrella-42 today?"  # noqa: S105
    caplog.set_level(logging.DEBUG)
    res = ask(client, match_id, token, {"role": "coach", "question": secret_question})
    assert res.json()["generation"] == "generated"
    cols = [
        r[0]
        for r in conn.execute(
            "select column_name from information_schema.columns where table_schema = 'public'"
            " and table_name = 'conversation_events' and data_type in ('text', 'character varying')"
        )
    ]
    assert cols
    for col in cols:
        sql = f"select {col} from public.conversation_events"  # noqa: S608
        values = [r[0] for r in conn.execute(sql)]
        flat = json.dumps(values, default=str)
        assert "zebra-umbrella" not in flat and token not in flat
    logged = "\n".join(r.getMessage() for r in caplog.records)
    assert "zebra-umbrella" not in logged and token not in logged


def test_retention_purge_deletes_old_events_and_keeps_today(client, conn, connect, match_id, token):
    from shared.db.conversation_events import PgConversationEventRepository

    assert ask(client, match_id, token).status_code == 200
    assert ask(client, match_id, token).status_code == 200
    conn.execute(
        "update public.conversation_events set occurred_at = now() - interval '31 days'"
        " where id = (select id from public.conversation_events order by occurred_at limit 1)"
    )
    PgConversationEventRepository(connect).purge(timedelta(days=30))
    [(remaining,)] = conn.execute("select count(*) from public.conversation_events").fetchall()
    assert remaining == 1
    [(old,)] = conn.execute(
        "select count(*) from public.conversation_events"
        " where occurred_at < now() - interval '30 days'"
    ).fetchall()
    assert old == 0
