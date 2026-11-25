"""POST /conversation: a general question without a match ("rules yes, today no", B6).

The answer check in general mode (no assessment, approved documents only) and the route end to
end (local PostgreSQL, fake AI providers, no network).
"""

import json

import pytest

from services.conversation.guard import check_answer
from services.rag.context_builder.builder import build_general_context
from services.rag.retrieval.hybrid import RetrievalResult
from tests.conftest import requires_db
from tests.conversation import test_conversation_api as base
from tests.conversation.test_guard_and_context import CHUNK, RULES, reply

API, FakeEmbedder, FakeGenerator = base.API, base.FakeEmbedder, base.FakeGenerator
ai, client, token = base.ai, base.client, base.token  # the same pytest fixtures

# --- the answer check without a match ---------------------------------------------------------

GENERAL = build_general_context(RetrievalResult([CHUNK], "hybrid"))
HOT = "Is 35°C too hot?"

GENERAL_CASES = [
    ("When are cooling breaks used?", "FIFA uses 3 minutes cooling breaks after about 30 and 75 "
     "minutes of play when the WBGT is 32 °C or more [D1]. The match management team decides.",
     "OK"),
    ("When are cooling breaks needed?", "Cooling breaks are required when the WBGT is 32 °C or "
     "more [D1].", "OK"),
    ("When are cooling breaks needed?", "At or above the cooling-break level (WBGT 32 °C), FIFA "
     "uses cooling breaks [D1].", "OK"),
    ("Can we play today?", "Pitchy cannot comment on current conditions without a match. FIFA "
     "uses 3 minutes cooling breaks [D1].", "OK"),
    (HOT, "The 35 °C you mentioned is not something Pitchy can assess without a match. FIFA "
     "uses cooling breaks when the WBGT is 32 °C or more [D1].", "OK"),
    # level wording must sit in a sentence that cites a document
    ("When are cooling breaks needed?", "Cooling breaks are required at high heat. FIFA "
     "describes this [D1].", "LEVEL_NOT_FROM_DOCUMENT"),
    ("When are cooling breaks needed?", "Status cooling_breaks_required [D1].", "LEVEL_NOT_GIVEN"),
    # a document must be cited; [A] only says there is no match
    ("When are cooling breaks needed?", "No match is selected [A].", "NO_DOCUMENT_CITATION"),
    # nothing about current or coming conditions
    ("Can we play today?", "Today the WBGT is 32 °C, so cooling breaks are used [D1].",
     "CURRENT_CONDITIONS"),
    ("Do we stop?", "For this match, cooling breaks of 3 minutes are used [D1].",
     "CURRENT_CONDITIONS"),
    ("Is it hot?", "Right now cooling breaks of 3 minutes apply [D1].", "CURRENT_CONDITIONS"),
    ("Mainit ba?", "Ngayon, cooling breaks of 3 minutes apply [D1].", "CURRENT_CONDITIONS"),
    # never "safe", never an invented number
    ("Can we play?", "Below 32 °C it is safe to play [D1].", "SAFETY_CLAIM"),
    ("How long?", "Cooling breaks last 5 minutes [D1].", "UNGROUNDED_NUMBER"),
    (HOT, "The 35 °C you mentioned is above the limit [D1].", "UNGROUNDED_NUMBER"),
    # numbers in words, as seen in the live answer
    ("When are breaks?", "Cooling breaks come at the thirtieth and seventy-fifth minutes [D1].",
     "OK"),
    ("When are breaks?", "FIFA measures the WBGT ninety minutes before kickoff [D1].",
     "UNGROUNDED_NUMBER"),
]  # fmt: skip


@pytest.mark.parametrize(("question", "answer", "expected"), GENERAL_CASES)
def test_general_answer_check(question, answer, expected) -> None:
    sources = ("A",) if expected == "NO_DOCUMENT_CITATION" else ("D1",)
    result = check_answer(reply(answer, sources), GENERAL, RULES, question)
    assert result.reason == expected, f"{answer!r} -> {result.reason}"


def test_general_context_has_no_assessment() -> None:
    assert GENERAL.general and GENERAL.classifications == {}
    assert "No match is selected" in GENERAL.facts
    assert GENERAL.labels == {"A", "D1"}


# --- the route ----------------------------------------------------------------------------------

RULES_ANSWER = json.dumps({
    "answer": "FIFA uses 3 minutes cooling breaks when the WBGT is 32 °C or more [D1]. The match "
    "management team decides.",
    "sources": ["D1"],
})  # fmt: skip
TODAY_ANSWER = json.dumps({"answer": "Today cooling breaks of 3 minutes apply [D1].",
                           "sources": ["D1"]})  # fmt: skip
QUESTION = {"role": "coach", "question": "When does FIFA use cooling breaks?"}


@pytest.fixture
def rules_doc(conn):
    from services.ai_providers.base import EMBEDDING_DIMENSIONS

    doc = conn.execute(
        "insert into public.protocol_documents (title, authority, version, document_key,"
        " approval_status) values ('FIFA Emergency Care Manual', 'FIFA', '2022',"
        " 'fifa_ecm_2022', 'approved') returning id"
    ).fetchone()[0]
    vector = "[" + ",".join(["1"] + ["0"] * (EMBEDDING_DIMENSIONS - 1)) + "]"
    conn.execute(
        "insert into public.protocol_chunks (document_id, position, section, content, embedding,"
        " embedding_model) values (%s, 0, 'Chapter 9', 'Cooling breaks of 3 minutes are used"
        " when the WBGT is 32 °C or more. The match management team decides.',"
        " %s::extensions.vector, 'fake-embed')",
        (doc, vector),
    )


def ask(client, token, body=QUESTION):
    headers = {"X-Session-Token": token} if token else {}
    return client.post(f"{API}/conversation", json=body, headers=headers)


def codes(res):
    return [lim["code"] for lim in res.json()["limitations"]]


def message(res, code):
    """The message of one limitation; a no-match reply never mentions a match or assessment."""
    texts = {lim["code"]: lim["message"] for lim in res.json()["limitations"]}
    for text in texts.values():
        low = text.lower()
        assert "match's" not in low and "assessment still applies" not in low, text
        assert "of the assessment" not in low, text
    return texts[code]


def event(conn):
    return conn.execute(
        "select match_context_id, assessment_id, outcome_code, provider_called, provider"
        " from public.conversation_events order by occurred_at desc limit 1"
    ).fetchone()


def slots(conn):
    row = conn.execute("select coalesce(sum(reserved), 0) from public.chat_daily_ai_usage")
    return row.fetchone()[0]


@requires_db
def test_rules_question_gets_a_general_answer(client, conn, ai, token, rules_doc) -> None:
    ai["generators"] = [FakeGenerator("gemini", [RULES_ANSWER])]
    res = ask(client, token)
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["generation"] == "generated" and "32 °C" in body["answer"]
    assert "match_context_id" not in body and "assessment_id" not in body
    assert codes(res)[:2] == ["AGENT_NOT_AUTHORITY", "GENERAL_GUIDANCE_ONLY"]
    assert [r["document_id"] for r in body["references"]] == ["fifa_ecm_2022"]
    assert event(conn) == (None, None, "GENERATED", True, "gemini")
    assert slots(conn) == 1


@requires_db
def test_talk_about_today_is_rejected_then_next_provider(client, conn, ai, token, rules_doc):
    first = FakeGenerator("gemini", [TODAY_ANSWER])
    ai["generators"] = [first, FakeGenerator("groq", [RULES_ANSWER])]
    body = ask(client, token).json()
    assert first.calls == 1 and body["generation"] == "generated"
    assert event(conn)[4] == "groq"


@requires_db
def test_every_reply_about_today_fails_the_check(client, conn, ai, token, rules_doc) -> None:
    ai["generators"] = [FakeGenerator("gemini", [TODAY_ANSWER])]
    res = ask(client, token)
    assert res.json()["answer"] is None and codes(res)[-1] == "ANSWER_CHECK_FAILED"
    assert message(res, "ANSWER_CHECK_FAILED") == (
        "No AI answer passed Pitchy's safety check, so none is shown."
    )
    assert slots(conn) == 1  # a provider was called


@requires_db
def test_no_matching_document_never_calls_the_ai(client, conn, ai, token) -> None:
    res = ask(client, token)
    assert res.status_code == 200
    assert res.json()["answer"] is None and "NO_GUIDANCE_FOUND" in codes(res)
    assert ai["generators"][0].calls == 0
    assert event(conn)[2:4] == ("NO_GUIDANCE_FOUND", False)
    assert slots(conn) == 0  # the daily slot was given back


@requires_db
def test_off_topic_never_reaches_the_ai(client, conn, ai, token, rules_doc) -> None:
    res = ask(client, token, {"role": "spectator", "question": "Write me a poem about cats"})
    assert codes(res)[-1] == "OFF_TOPIC" and ai["generators"][0].calls == 0
    assert slots(conn) == 0
    assert message(res, "OFF_TOPIC").startswith("I can only help with weather safety for football")


@requires_db
def test_keyword_only_search_is_flagged(client, ai, token, rules_doc) -> None:
    ai["generators"] = [FakeGenerator("gemini", [RULES_ANSWER])]
    ai["embedder"] = FakeEmbedder(fail=True)
    assert "RETRIEVAL_KEYWORD_ONLY" in codes(ask(client, token))


@requires_db
def test_missing_token_is_401(client) -> None:
    res = ask(client, None)
    assert res.status_code == 401 and res.json()["error"]["code"] == "INVALID_SESSION"


@requires_db
def test_shares_the_per_session_limit(client, ai, token, rules_doc) -> None:
    ai["generators"] = [FakeGenerator("gemini", [RULES_ANSWER] * 10)]
    assert all(ask(client, token).status_code == 200 for _ in range(10))
    res = ask(client, token)
    assert res.status_code == 429 and res.json()["error"]["retry_at"]


@requires_db
def test_daily_cap_applies(client, conn, ai, token, rules_doc) -> None:
    conn.execute(
        "insert into public.chat_daily_ai_usage (day, reserved)"
        " values ((now() at time zone interval '8 hours')::date, 500)"
    )
    res = ask(client, token)
    assert "DAILY_LIMIT_REACHED" in codes(res) and ai["generators"][0].calls == 0
    assert message(res, "DAILY_LIMIT_REACHED").endswith("Try again tomorrow.")


@requires_db
def test_general_rows_are_purged_after_30_days(client, conn, connect, ai, token, rules_doc):
    from datetime import timedelta

    from shared.db.conversation_events import PgConversationEventRepository

    ai["generators"] = [FakeGenerator("gemini", [RULES_ANSWER])]
    ask(client, token)
    conn.execute("update public.conversation_events set occurred_at = now() - interval '31 days'")
    deleted = PgConversationEventRepository(connect).purge(timedelta(days=30))
    assert deleted["conversation_events_deleted"] == 1


@requires_db
def test_authority_note_names_guidance_not_an_assessment(client, ai, token, rules_doc) -> None:
    res = ask(client, token, {"role": "coach", "question": "What is the capital of France?"})
    assert message(res, "AGENT_NOT_AUTHORITY") == (
        "AI-generated explanation of approved guidance. Officials make the decision."
    )


def test_provider_failure_message_has_no_assessment(client, ai, token, rules_doc) -> None:
    from services.ai_providers.base import ProviderError

    ai["generators"] = [FakeGenerator("gemini", [ProviderError("TIMEOUT")])]
    res = ask(client, token)
    assert message(res, "AI_UNAVAILABLE") == (
        "The AI explanation is unavailable right now. Try again later."
    )
