"""Smoke test of the real AI providers (B5 plan section 6). Run it by hand from the PC.

Run from ``backend/``::

    uv run python scripts/smoke_ai.py

Uses the keys in the root ``.env`` (GEMINI_API_KEY, GROQ_API_KEY, OPENROUTER_API_KEY). Sends one
tiny request to each provider and one embedding to Gemini; no match data and nothing personal is
sent. It prints only the provider, the model, OK or an error code, and the time taken. It never
prints a key, a URL or a full answer. No database is used.
"""

import sys
import time
from pathlib import Path

BACKEND_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND_DIR))

from services.ai_providers.base import EMBEDDING_DIMENSIONS, ProviderError  # noqa: E402
from services.ai_providers.factory import build_embedder, build_generators  # noqa: E402
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


def main() -> int:
    settings = Settings()
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
