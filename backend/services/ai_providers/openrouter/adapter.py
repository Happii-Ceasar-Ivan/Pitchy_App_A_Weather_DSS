"""OpenRouter (DEC-10, fallback 2): OpenAI-compatible chat completions on free models only.

No referer or title headers are sent, so nothing identifies the app or the user.
"""

import httpx
from pydantic import SecretStr

from services.ai_providers.openai_compat import OpenAICompatGenerator

OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
OPENROUTER_MODEL = "openrouter/free"


class OpenRouterGenerator(OpenAICompatGenerator):
    def __init__(
        self, api_key: SecretStr | None, transport: httpx.BaseTransport | None = None
    ) -> None:
        super().__init__(
            name="openrouter",
            url=OPENROUTER_URL,
            model=OPENROUTER_MODEL,
            api_key=api_key,
            transport=transport,
        )
