"""scripts/smoke_ai.py with fake transports: never a real network call, never a key in output."""

import json

import httpx
from pydantic import SecretStr

from scripts.smoke_ai import check_embedder, check_generators, list_models, try_gemini
from shared.settings import Settings

KEY = "secret-key-123"


def _reply(request: httpx.Request) -> httpx.Response:
    if "batchEmbedContents" in request.url.path:
        return httpx.Response(200, json={"embeddings": [{"values": [0.1] * 768}]})
    if "generativelanguage" in request.url.host:
        text = json.dumps({"answer": "ok", "sources": []})
        return httpx.Response(200, json={"candidates": [{"content": {"parts": [{"text": text}]}}]})
    return httpx.Response(429)


def test_reports_ok_codes_and_missing_keys_without_secrets(capsys) -> None:
    settings = Settings(env="test", gemini_api_key=SecretStr(KEY), groq_api_key=SecretStr(KEY),
                        openrouter_api_key=None)  # fmt: skip
    transport = httpx.MockTransport(_reply)
    results = dict(check_generators(settings, transport))
    assert results["gemini"].startswith("OK (model ")
    assert results["groq"].startswith("RATE_LIMITED")
    assert results["openrouter"] == "NOT_CONFIGURED"
    assert check_embedder(settings, transport).startswith("OK (model gemini-embedding-001, 768/768")
    assert KEY not in "".join(results.values()) + capsys.readouterr().out


def test_list_models_reads_names_only() -> None:
    def models(request: httpx.Request) -> httpx.Response:
        assert request.method == "GET" and KEY not in str(request.url)
        if "googleapis" in request.url.host:
            return httpx.Response(200, json={"models": [
                {"name": "models/gemini-x", "supportedGenerationMethods": ["generateContent"]},
                {"name": "models/embed-only", "supportedGenerationMethods": ["embedContent"]},
            ]})  # fmt: skip
        return httpx.Response(200, json={"data": [{"id": "model-b"}, {"id": "model-a"}]})

    settings = Settings(env="test", gemini_api_key=SecretStr(KEY), groq_api_key=SecretStr(KEY))
    assert list_models(settings, httpx.MockTransport(models)) == {
        "gemini": ["gemini-x"],
        "groq": ["model-a", "model-b"],
    }


def test_try_gemini_reports_each_model() -> None:
    def reply(request: httpx.Request) -> httpx.Response:
        if "busy-model" in request.url.path:
            return httpx.Response(503)
        text = json.dumps({"answer": "ok", "sources": []})
        return httpx.Response(200, json={"candidates": [{"content": {"parts": [{"text": text}]}}]})

    settings = Settings(env="test", gemini_api_key=SecretStr(KEY))
    results = dict(try_gemini(settings, ("busy-model", "free-model"), httpx.MockTransport(reply)))
    assert results["busy-model"].startswith("HTTP_503")
    assert results["free-model"].startswith("OK (")
