"""AI provider adapters, router and factory. httpx.MockTransport only; no real network."""

import json
import logging
from types import SimpleNamespace

import httpx
import pytest
from pydantic import SecretStr

from services.ai_providers.base import EMBEDDING_DIMENSIONS, Generation, ProviderError
from services.ai_providers.factory import build_embedder, build_generators
from services.ai_providers.gemini.adapter import GeminiEmbedder, GeminiGenerator
from services.ai_providers.groq.adapter import GroqGenerator
from services.ai_providers.openrouter.adapter import OpenRouterGenerator
from services.ai_providers.provider_router.router import ProviderRouter

KEYS = {"gemini": "gem-KEY-111", "groq": "groq-KEY-222", "openrouter": "or-KEY-333"}
SYSTEM = "SYSTEM-SECRET-TEXT"
PROMPT = "PROMPT-SECRET-TEXT"
ANSWER = '{"answer": "ANSWER-SECRET-TEXT"}'


def _settings(**present: bool):
    def key(name: str):
        return SecretStr(KEYS[name]) if present.get(name, True) else None

    return SimpleNamespace(
        gemini_api_key=key("gemini"), groq_api_key=key("groq"), openrouter_api_key=key("openrouter")
    )


def _ok_body(host: str) -> dict:
    if host.startswith("generativelanguage"):
        return {"candidates": [{"content": {"parts": [{"text": ANSWER}]}}]}
    return {"choices": [{"message": {"content": ANSWER}}]}


class Recorder:
    """MockTransport handler: per-host behaviour, records every request."""

    def __init__(self, behaviour: dict | None = None) -> None:
        self.behaviour = behaviour or {}
        self.requests: list[httpx.Request] = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        host = request.url.host
        action = self.behaviour.get(host, "ok")
        if action == "ok":
            return httpx.Response(200, json=_ok_body(host))
        if action == "timeout":
            raise httpx.ReadTimeout("slow", request=request)
        if action == "network":
            raise httpx.ConnectError("down", request=request)
        if action == "badjson":
            return httpx.Response(200, content=b"not json")
        if action == "empty":
            return httpx.Response(200, json={"choices": [{"message": {"content": "  "}}]})
        return httpx.Response(int(action), json={"error": "BODY-SECRET"})

    @property
    def hosts(self) -> list[str]:
        return [r.url.host for r in self.requests]


def _router(rec: Recorder, settings=None, **kw) -> ProviderRouter:
    gens = build_generators(settings or _settings(), httpx.MockTransport(rec))
    return ProviderRouter(gens, **kw)


def _accept_all(_: Generation) -> bool:
    return True


def test_order_and_first_success_stops():
    rec = Recorder()
    result = _router(rec).run(SYSTEM, PROMPT, _accept_all)
    assert result.generation is not None
    assert result.generation.provider == "gemini"
    assert result.attempts == [("gemini", "OK")]
    assert result.provider_called
    assert rec.hosts == ["generativelanguage.googleapis.com"]


def test_generators_in_fixed_order():
    assert [g.name for g in build_generators(_settings())] == ["gemini", "groq", "openrouter"]


@pytest.mark.parametrize(
    ("action", "code"),
    [
        (429, "RATE_LIMITED"),
        ("timeout", "TIMEOUT"),
        (500, "HTTP_500"),
        ("badjson", "BAD_RESPONSE"),
        ("network", "NETWORK"),
    ],
)
def test_failure_falls_to_next_provider(action, code):
    rec = Recorder({"generativelanguage.googleapis.com": action})
    result = _router(rec).run(SYSTEM, PROMPT, _accept_all)
    assert result.generation is not None and result.generation.provider == "groq"
    assert result.attempts == [("gemini", code), ("groq", "OK")]


def test_missing_key_skipped_without_request():
    rec = Recorder()
    result = _router(rec, _settings(gemini=False)).run(SYSTEM, PROMPT, _accept_all)
    assert result.attempts == [("gemini", "NOT_CONFIGURED"), ("groq", "OK")]
    assert "generativelanguage.googleapis.com" not in rec.hosts


def test_nothing_configured_means_no_provider_called():
    rec = Recorder()
    s = _settings(gemini=False, groq=False, openrouter=False)
    result = _router(rec, s).run(SYSTEM, PROMPT, _accept_all)
    assert result.generation is None
    assert not result.provider_called
    assert rec.requests == []
    assert [c for _, c in result.attempts] == ["NOT_CONFIGURED"] * 3
    assert build_embedder(s) is None


def test_rejected_answer_tries_next():
    rec = Recorder()
    seen: list[str] = []

    def accept(g: Generation) -> bool:
        seen.append(g.provider)
        return g.provider == "openrouter"

    result = _router(rec).run(SYSTEM, PROMPT, accept)
    assert seen == ["gemini", "groq", "openrouter"]
    assert result.attempts == [
        ("gemini", "ANSWER_REJECTED"),
        ("groq", "ANSWER_REJECTED"),
        ("openrouter", "OK"),
    ]
    assert result.generation is not None and result.generation.provider == "openrouter"


def test_all_fail_records_every_attempt():
    rec = Recorder(
        {
            "generativelanguage.googleapis.com": 429,
            "api.groq.com": "timeout",
            "openrouter.ai": 503,
        }
    )
    result = _router(rec).run(SYSTEM, PROMPT, _accept_all)
    assert result.generation is None
    assert result.provider_called
    assert result.attempts == [
        ("gemini", "RATE_LIMITED"),
        ("groq", "TIMEOUT"),
        ("openrouter", "HTTP_503"),
    ]


def test_empty_text_is_bad_response():
    rec = Recorder({"api.groq.com": "empty"})
    gen = GroqGenerator(SecretStr("k"), httpx.MockTransport(rec))
    with pytest.raises(ProviderError) as info:
        gen.generate(SYSTEM, PROMPT, timeout_s=5)
    assert info.value.code == "BAD_RESPONSE"


class _Slow:
    def __init__(self, name, clock, cost, fail=True):
        self.name, self._clock, self._cost, self._fail = name, clock, cost, fail
        self.configured = True
        self.timeouts: list[float] = []

    def generate(self, system, prompt, *, timeout_s):
        self.timeouts.append(timeout_s)
        self._clock.now += self._cost
        raise ProviderError("TIMEOUT")


class _Clock:
    now = 0.0

    def __call__(self):
        return self.now


def test_budget_stops_early_and_caps_timeouts():
    clock = _Clock()
    a = _Slow("gemini", clock, 15)
    b = _Slow("groq", clock, 15)
    c = _Slow("openrouter", clock, 15)
    router = ProviderRouter([a, b, c], per_call_timeout_s=15, total_timeout_s=20, clock=clock)
    result = router.run(SYSTEM, PROMPT, _accept_all)
    assert a.timeouts == [15] and b.timeouts == [5]
    assert c.timeouts == []
    assert result.attempts == [
        ("gemini", "TIMEOUT"),
        ("groq", "TIMEOUT"),
        ("openrouter", "BUDGET_EXHAUSTED"),
    ]


def test_keys_in_headers_never_in_url():
    rec = Recorder()
    _router(rec).run(SYSTEM, PROMPT, lambda g: False)
    assert len(rec.requests) == 3
    for req in rec.requests:
        assert not any(k in str(req.url) for k in KEYS.values())
        assert req.url.scheme == "https" and not req.url.query
    by_host = {r.url.host: r for r in rec.requests}
    assert by_host["generativelanguage.googleapis.com"].headers["x-goog-api-key"] == KEYS["gemini"]
    assert by_host["api.groq.com"].headers["authorization"] == f"Bearer {KEYS['groq']}"
    assert by_host["openrouter.ai"].headers["authorization"] == f"Bearer {KEYS['openrouter']}"
    for name in ("referer", "http-referer", "x-title"):
        assert name not in by_host["openrouter.ai"].headers


def test_request_body_shapes():
    rec = Recorder()
    _router(rec).run(SYSTEM, PROMPT, lambda g: False)
    gem, groq, orr = (json.loads(r.content) for r in rec.requests)
    assert rec.requests[0].url.path.endswith(":generateContent")
    assert gem["systemInstruction"]["parts"][0]["text"] == SYSTEM
    assert gem["contents"][0]["parts"][0]["text"] == PROMPT
    cfg = gem["generationConfig"]
    assert cfg["temperature"] == 0.2
    assert cfg["responseMimeType"] == "application/json"
    assert 0 < cfg["maxOutputTokens"] <= 1000
    for body, model in ((groq, "llama-3.3-70b-versatile"), (orr, "openrouter/free")):
        assert body["model"] == model
        assert body["messages"] == [
            {"role": "system", "content": SYSTEM},
            {"role": "user", "content": PROMPT},
        ]
        assert body["temperature"] == 0.2
        assert body["response_format"] == {"type": "json_object"}
        assert 0 < body["max_tokens"] <= 1000


def test_no_secrets_in_logs_or_errors(caplog):
    caplog.set_level(logging.DEBUG)
    rec = Recorder({"generativelanguage.googleapis.com": 500, "api.groq.com": "timeout"})
    _router(rec).run(SYSTEM, PROMPT, _accept_all)
    gen = GeminiGenerator(
        SecretStr(KEYS["gemini"]),
        httpx.MockTransport(Recorder({"generativelanguage.googleapis.com": 500})),
    )
    with pytest.raises(ProviderError) as info:
        gen.generate(SYSTEM, PROMPT, timeout_s=5)
    assert str(info.value) == "HTTP_500" and info.value.args == ("HTTP_500",)
    assert info.value.__cause__ is None
    text = caplog.text + repr(info.value)
    for secret in [
        *KEYS.values(),
        SYSTEM,
        PROMPT,
        "ANSWER-SECRET-TEXT",
        "BODY-SECRET",
        "googleapis.com",
        "groq.com",
        "openrouter.ai",
        "https://",
    ]:
        assert secret not in text


def test_unconfigured_adapter_raises_not_configured():
    gen = GeminiGenerator(None)
    assert not gen.configured
    with pytest.raises(ProviderError) as info:
        gen.generate(SYSTEM, PROMPT, timeout_s=5)
    assert info.value.code == "NOT_CONFIGURED"


def test_redirects_not_followed():
    def handler(request):
        return httpx.Response(302, headers={"location": "https://evil.example/x"})

    gen = OpenRouterGenerator(SecretStr("k"), httpx.MockTransport(handler))
    with pytest.raises(ProviderError) as info:
        gen.generate(SYSTEM, PROMPT, timeout_s=5)
    assert info.value.code == "HTTP_302"


# --- embedder -------------------------------------------------------------------------------


def _embed_handler(requests, dims=EMBEDDING_DIMENSIONS, value=0.1):
    def handler(request):
        requests.append(request)
        n = len(json.loads(request.content)["requests"])
        return httpx.Response(200, json={"embeddings": [{"values": [value] * dims}] * n})

    return handler


def test_embedder_batches_of_100():
    reqs: list[httpx.Request] = []
    emb = GeminiEmbedder(SecretStr(KEYS["gemini"]), httpx.MockTransport(_embed_handler(reqs)))
    vectors = emb.embed([f"t{i}" for i in range(150)], task="document")
    assert len(vectors) == 150 and len(vectors[0]) == EMBEDDING_DIMENSIONS
    assert [len(json.loads(r.content)["requests"]) for r in reqs] == [100, 50]
    assert emb.model == "gemini-embedding-001"
    assert all(r.headers["x-goog-api-key"] == KEYS["gemini"] for r in reqs)
    assert all(KEYS["gemini"] not in str(r.url) for r in reqs)
    assert reqs[0].url.path.endswith("gemini-embedding-001:batchEmbedContents")


@pytest.mark.parametrize(
    ("task", "expected"), [("document", "RETRIEVAL_DOCUMENT"), ("query", "RETRIEVAL_QUERY")]
)
def test_embedder_task_mapping_and_body(task, expected):
    reqs: list[httpx.Request] = []
    emb = GeminiEmbedder(SecretStr("k"), httpx.MockTransport(_embed_handler(reqs)))
    emb.embed(["hello"], task=task)
    item = json.loads(reqs[0].content)["requests"][0]
    assert item["taskType"] == expected
    assert item["outputDimensionality"] == EMBEDDING_DIMENSIONS
    assert item["model"] == "models/gemini-embedding-001"
    assert item["content"]["parts"][0]["text"] == "hello"


def test_embedder_wrong_dimension_is_bad_response():
    emb = GeminiEmbedder(SecretStr("k"), httpx.MockTransport(_embed_handler([], dims=3)))
    with pytest.raises(ProviderError) as info:
        emb.embed(["x"], task="query")
    assert info.value.code == "BAD_RESPONSE"


def test_embedder_non_finite_is_bad_response():
    handler = _embed_handler([], value=float("nan"))

    def raw(request):
        n = len(json.loads(request.content)["requests"])
        body = '{"embeddings": [{"values": [' + ",".join(["NaN"] * EMBEDDING_DIMENSIONS) + "]}]}"
        assert n == 1
        return httpx.Response(
            200, content=body.encode(), headers={"content-type": "application/json"}
        )

    del handler
    emb = GeminiEmbedder(SecretStr("k"), httpx.MockTransport(raw))
    with pytest.raises(ProviderError) as info:
        emb.embed(["x"], task="query")
    assert info.value.code == "BAD_RESPONSE"


def test_embedder_count_mismatch_and_errors():
    def short(request):
        return httpx.Response(200, json={"embeddings": []})

    with pytest.raises(ProviderError) as info:
        GeminiEmbedder(SecretStr("k"), httpx.MockTransport(short)).embed(["x"], task="query")
    assert info.value.code == "BAD_RESPONSE"

    def limited(request):
        return httpx.Response(429)

    with pytest.raises(ProviderError) as info:
        GeminiEmbedder(SecretStr("k"), httpx.MockTransport(limited)).embed(["x"], task="query")
    assert info.value.code == "RATE_LIMITED"


def test_build_embedder():
    assert isinstance(build_embedder(_settings()), GeminiEmbedder)
    assert build_embedder(_settings(gemini=False)) is None
