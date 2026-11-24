"""OpenAI-compatible chat adapter shared by Groq and OpenRouter."""

import httpx
from pydantic import SecretStr

from services.ai_providers.base import Generation, ProviderError, ProviderName
from services.ai_providers.http_util import post_json

TEMPERATURE = 0.2
MAX_OUTPUT_TOKENS = 2048  # reasoning tokens count too; the answer check limits the answer length


class OpenAICompatGenerator:
    def __init__(
        self,
        *,
        name: ProviderName,
        url: str,
        model: str,
        api_key: SecretStr | None,
        transport: httpx.BaseTransport | None = None,
    ) -> None:
        self.name: ProviderName = name
        self.model = model
        self._url = url
        self._key = api_key.get_secret_value() if api_key else ""
        self._transport = transport

    @property
    def configured(self) -> bool:
        return bool(self._key)

    def generate(self, system: str, prompt: str, *, timeout_s: float) -> Generation:
        if not self.configured:
            raise ProviderError("NOT_CONFIGURED")
        data = post_json(
            self._url,
            headers={"Authorization": f"Bearer {self._key}"},
            body={
                "model": self.model,
                "messages": [
                    {"role": "system", "content": system},
                    {"role": "user", "content": prompt},
                ],
                "temperature": TEMPERATURE,
                "max_tokens": MAX_OUTPUT_TOKENS,
                "response_format": {"type": "json_object"},
            },
            timeout_s=timeout_s,
            transport=self._transport,
        )
        try:
            text = data["choices"][0]["message"]["content"]
        except KeyError, IndexError, TypeError:
            raise ProviderError("BAD_RESPONSE") from None
        if not isinstance(text, str) or not text.strip():
            raise ProviderError("BAD_RESPONSE")
        return Generation(provider=self.name, model=self.model, text=text)
