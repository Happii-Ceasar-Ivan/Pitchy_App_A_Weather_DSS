"""Smoke test of the real AI providers (B5 plan section 6). Run it by hand from the PC.

Run from ``backend/``::

    uv run python scripts/smoke_ai.py                # one tiny request per provider
    uv run python scripts/smoke_ai.py --list-models  # which model names each key can use now
    uv run python scripts/smoke_ai.py --try-gemini   # test several Gemini models in one go

Uses the keys in the root ``.env`` (GEMINI_API_KEY, GROQ_API_KEY, OPENROUTER_API_KEY). Sends one
tiny request to each provider and one embedding to Gemini; no match data and nothing personal is
sent. It prints only the provider, the model, OK or an error code, and the time taken. It never
prints a key, a URL or a full answer. No database is used.
"""

import sys
import time
from pathlib import Path

import httpx

BACKEND_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND_DIR))

from services.ai_providers.base import EMBEDDING_DIMENSIONS, ProviderError  # noqa: E402
from services.ai_providers.factory import build_embedder, build_generators  # noqa: E402
from services.ai_providers.gemini.adapter import GeminiGenerator  # noqa: E402
from services.conversation.guard import _parse  # noqa: E402
from shared.settings import Settings  # noqa: E402

SYSTEM = 'Reply with JSON only: {"answer": "ok", "sources": []}'
PROMPT = "This is a connection test. Reply with the JSON shown in the instructions."


def check_generators(settings: Settings, transport=None) -> list[tuple[str, str]]:
    results = []
    for gen in build_generators(settings, transport):
        if not gen.configured:
            results.append((gen.name, "NOT_CONFIGURED"))
            continue
        started = time.monotonic()
        try:
            reply = gen.generate(SYSTEM, PROMPT, timeout_s=20.0)
        except ProviderError as exc:
            outcome = exc.code
        else:
            outcome = "OK" if _parse(reply.text) is not None else "OK_BUT_NOT_JSON"
        seconds = time.monotonic() - started
        results.append((gen.name, f"{outcome} (model {gen.model}, {seconds:.1f} s)"))
    return results


def check_embedder(settings: Settings, transport=None) -> str:
    embedder = build_embedder(settings, transport)
    if embedder is None:
        return "NOT_CONFIGURED"
    try:
        vector = embedder.embed(["connection test"], task="query")[0]
    except ProviderError as exc:
        return exc.code
    return f"OK (model {embedder.model}, {len(vector)}/{EMBEDDING_DIMENSIONS} dimensions)"


# Read-only model lists (GET). Fixed URLs; keys in headers; never printed.
_GEMINI_MODELS = "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1000"
_GROQ_MODELS = "https://api.groq.com/openai/v1/models"


def list_models(settings: Settings, transport=None) -> dict[str, list[str]]:
    """Model names each configured key can use for text generation, or an error code."""
    out: dict[str, list[str]] = {}
    targets = []
    if settings.gemini_api_key:
        key = settings.gemini_api_key.get_secret_value()
        targets.append(("gemini", _GEMINI_MODELS, {"x-goog-api-key": key}))
    if settings.groq_api_key:
        key = settings.groq_api_key.get_secret_value()
        targets.append(("groq", _GROQ_MODELS, {"Authorization": f"Bearer {key}"}))
    for name, url, headers in targets:
        try:
            with httpx.Client(timeout=20.0, follow_redirects=False, transport=transport) as c:
                response = c.get(url, headers=headers)
        except httpx.HTTPError:
            out[name] = ["NETWORK"]
            continue
        if response.status_code != 200:
            out[name] = [f"HTTP_{response.status_code}"]
            continue
        data = response.json()
        if name == "gemini":
            ids = [
                m.get("name", "").removeprefix("models/")
                for m in data.get("models", [])
                if "generateContent" in m.get("supportedGenerationMethods", [])
            ]
        else:
            ids = [m.get("id", "") for m in data.get("data", []) if m.get("active", True)]
        out[name] = sorted(i for i in ids if i)
    return out


# Free-tier Flash / Flash-Lite names seen in the key's model list on 2026-11-25.
GEMINI_CANDIDATES = (
    "gemini-flash-latest", "gemini-flash-lite-latest", "gemini-3.5-flash", "gemini-3.5-flash-lite",
    "gemini-3.1-flash-lite", "gemini-3-flash-preview", "gemini-3.7-flash", "gemini-3.8-flash",
)  # fmt: skip


def try_gemini(settings: Settings, models=GEMINI_CANDIDATES, transport=None) -> list[tuple]:
    """One tiny request per Gemini model name; returns (model, outcome)."""
    results = []
    for model in models:
        gen = GeminiGenerator(settings.gemini_api_key, transport, model=model)
        if not gen.configured:
            return [(model, "NOT_CONFIGURED") for model in models]
        started = time.monotonic()
        try:
            reply = gen.generate(SYSTEM, PROMPT, timeout_s=20.0)
        except ProviderError as exc:
            outcome = exc.code
        else:
            outcome = "OK" if _parse(reply.text) is not None else "OK_BUT_NOT_JSON"
        results.append((model, f"{outcome} ({time.monotonic() - started:.1f} s)"))
    return results


def main() -> int:
    settings = Settings()
    if "--try-gemini" in sys.argv[1:]:
        for model, outcome in try_gemini(settings):
            print(f"  {model:26} {outcome}")
        return 0
    if "--list-models" in sys.argv[1:]:
        for name, ids in list_models(settings).items():
            print(f"{name}:")
            for model_id in ids:
                print(f"  {model_id}")
        return 0
    results = check_generators(settings)
    for name, outcome in results:
        print(f"  {name:11} {outcome}")
    embedding = check_embedder(settings)
    print(f"  {'embedding':11} {embedding}")
    ok = any(o.startswith("OK ") for _, o in results) and embedding.startswith("OK ")
    print("At least one provider and the embedder work." if ok else "Not ready: see above.")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
