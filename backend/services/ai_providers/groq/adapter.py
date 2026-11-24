"""Groq (DEC-10, fallback 1): OpenAI-compatible chat completions."""

import httpx
from pydantic import SecretStr

from services.ai_providers.openai_compat import OpenAICompatGenerator

GROQ_URL = "https://api.groq.com/openai/v1/chat/completions"
GROQ_MODEL = "llama-3.3-70b-versatile"


class GroqGenerator(OpenAICompatGenerator):
    def __init__(
        self, api_key: SecretStr | None, transport: httpx.BaseTransport | None = None
    ) -> None:
        super().__init__(
            name="groq", url=GROQ_URL, model=GROQ_MODEL, api_key=api_key, transport=transport
        )
