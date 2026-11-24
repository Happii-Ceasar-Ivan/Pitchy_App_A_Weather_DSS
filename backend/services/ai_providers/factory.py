"""Builds the providers from settings, in the fixed DEC-10 order."""

import httpx

from services.ai_providers.base import TextGenerator
from services.ai_providers.gemini.adapter import GeminiEmbedder, GeminiGenerator
from services.ai_providers.groq.adapter import GroqGenerator
from services.ai_providers.openrouter.adapter import OpenRouterGenerator
from shared.settings import Settings


def build_generators(
    settings: Settings, transport: httpx.BaseTransport | None = None
) -> list[TextGenerator]:
    """Gemini, then Groq, then OpenRouter. Unconfigured ones stay in (the router skips them)."""
    return [
        GeminiGenerator(settings.gemini_api_key, transport),
        GroqGenerator(settings.groq_api_key, transport),
        OpenRouterGenerator(settings.openrouter_api_key, transport),
    ]


def build_embedder(
    settings: Settings, transport: httpx.BaseTransport | None = None
) -> GeminiEmbedder | None:
    embedder = GeminiEmbedder(settings.gemini_api_key, transport)
    return embedder if embedder.configured else None
