"""scripts/smoke_ai.py with fake transports: never a real network call, never a key in output."""

import json

import httpx
from pydantic import SecretStr

from scripts.smoke_ai import check_embedder, check_generators
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
