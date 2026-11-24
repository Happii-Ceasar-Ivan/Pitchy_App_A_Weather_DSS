"""Google Gemini (DEC-10 primary; DEC-09 embeddings) over the REST API. Key goes in a header."""

import math
from collections.abc import Sequence

import httpx
from pydantic import SecretStr

from services.ai_providers.base import (
    EMBEDDING_DIMENSIONS,
    EmbedTask,
    Generation,
    ProviderError,
)
from services.ai_providers.http_util import post_json

GEMINI_BASE_URL = "https://generativelanguage.googleapis.com/v1beta/models"
GEMINI_GENERATION_MODEL = "gemini-2.5-flash"
GEMINI_EMBEDDING_MODEL = "gemini-embedding-001"
TEMPERATURE = 0.2
MAX_OUTPUT_TOKENS = 600
EMBED_BATCH_SIZE = 100
EMBED_TIMEOUT_S = 30.0
_TASK_TYPES = {"document": "RETRIEVAL_DOCUMENT", "query": "RETRIEVAL_QUERY"}


def _key(api_key: SecretStr | None) -> str:
    return api_key.get_secret_value() if api_key else ""


class GeminiGenerator:
    name = "gemini"

    def __init__(
        self, api_key: SecretStr | None, transport: httpx.BaseTransport | None = None
    ) -> None:
        self.model = GEMINI_GENERATION_MODEL
        self._key = _key(api_key)
        self._transport = transport

    @property
    def configured(self) -> bool:
        return bool(self._key)

    def generate(self, system: str, prompt: str, *, timeout_s: float) -> Generation:
        if not self.configured:
            raise ProviderError("NOT_CONFIGURED")
        data = post_json(
            f"{GEMINI_BASE_URL}/{self.model}:generateContent",
            headers={"x-goog-api-key": self._key},
            body={
                "systemInstruction": {"parts": [{"text": system}]},
                "contents": [{"role": "user", "parts": [{"text": prompt}]}],
                "generationConfig": {
                    "temperature": TEMPERATURE,
                    "maxOutputTokens": MAX_OUTPUT_TOKENS,
                    "responseMimeType": "application/json",
                    # 2.5 Flash thinks by default, and thinking tokens count toward the output
                    # limit, which can leave no answer text. Short explanations need no thinking.
                    "thinkingConfig": {"thinkingBudget": 0},
                },
            },
            timeout_s=timeout_s,
            transport=self._transport,
        )
        try:
            parts = data["candidates"][0]["content"]["parts"]
            text = "".join(p["text"] for p in parts if isinstance(p.get("text"), str))
        except KeyError, IndexError, TypeError, AttributeError:
            raise ProviderError("BAD_RESPONSE") from None
        if not text.strip():
            raise ProviderError("BAD_RESPONSE")
        return Generation(provider="gemini", model=self.model, text=text)


class GeminiEmbedder:
    def __init__(
        self,
        api_key: SecretStr | None,
        transport: httpx.BaseTransport | None = None,
        timeout_s: float = EMBED_TIMEOUT_S,
    ) -> None:
        self.model = GEMINI_EMBEDDING_MODEL
        self._key = _key(api_key)
        self._transport = transport
        self._timeout_s = timeout_s

    @property
    def configured(self) -> bool:
        return bool(self._key)

    def embed(self, texts: Sequence[str], *, task: EmbedTask) -> list[list[float]]:
        if not self.configured:
            raise ProviderError("NOT_CONFIGURED")
        vectors: list[list[float]] = []
        for start in range(0, len(texts), EMBED_BATCH_SIZE):
            vectors.extend(self._embed_batch(texts[start : start + EMBED_BATCH_SIZE], task))
        return vectors

    def _embed_batch(self, batch: Sequence[str], task: EmbedTask) -> list[list[float]]:
        model_ref = f"models/{self.model}"
        data = post_json(
            f"{GEMINI_BASE_URL}/{self.model}:batchEmbedContents",
            headers={"x-goog-api-key": self._key},
            body={
                "requests": [
                    {
                        "model": model_ref,
                        "content": {"parts": [{"text": text}]},
                        "taskType": _TASK_TYPES[task],
                        "outputDimensionality": EMBEDDING_DIMENSIONS,
                    }
                    for text in batch
                ]
            },
            timeout_s=self._timeout_s,
            transport=self._transport,
        )
        try:
            raw = [item["values"] for item in data["embeddings"]]
        except KeyError, TypeError:
            raise ProviderError("BAD_RESPONSE") from None
        if len(raw) != len(batch):
            raise ProviderError("BAD_RESPONSE")
        out: list[list[float]] = []
        for values in raw:
            if (
                not isinstance(values, list)
                or len(values) != EMBEDDING_DIMENSIONS
                or not all(
                    isinstance(v, int | float) and not isinstance(v, bool) and math.isfinite(v)
                    for v in values
                )
            ):
                raise ProviderError("BAD_RESPONSE")
            out.append([float(v) for v in values])
        return out
