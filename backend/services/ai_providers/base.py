"""Shared AI provider interfaces (DEC-10, B5 plan 4.6). Change only with a tech-lead review.

Adapters (gemini, groq, openrouter) implement :class:`TextGenerator`; Gemini also implements
:class:`Embedder` (DEC-09). The RAG code (loader, retrieval) depends only on :class:`Embedder`, so
tests use fakes and never call a real provider.

Rules for every adapter:
- Keys go in request headers, never in URLs. Request URLs, prompts, answers and keys are never
  logged or put in exception messages.
- Fixed HTTPS base URLs from code constants only (no URL from settings or user input), no
  redirects followed, explicit timeouts.
- Failures raise :class:`ProviderError` with a short code; the router skips to the next provider.
"""

from collections.abc import Sequence
from dataclasses import dataclass
from typing import Literal, Protocol

ProviderName = Literal["gemini", "groq", "openrouter"]

EMBEDDING_DIMENSIONS = 768  # matches protocol_chunks.embedding vector(768)

EmbedTask = Literal["document", "query"]


class ProviderError(Exception):
    """A provider call failed. ``code`` is safe to store or log; it never holds secrets."""

    def __init__(self, code: str) -> None:
        # Codes: NOT_CONFIGURED, TIMEOUT, RATE_LIMITED, HTTP_<status>, BAD_RESPONSE, NETWORK
        super().__init__(code)
        self.code = code


@dataclass(frozen=True)
class Generation:
    provider: ProviderName
    model: str
    text: str


class TextGenerator(Protocol):
    name: ProviderName

    @property
    def configured(self) -> bool:
        """True when the provider's key is set."""
        ...

    def generate(self, system: str, prompt: str, *, timeout_s: float) -> Generation:
        """One completion. Raises ProviderError on any failure."""
        ...


class Embedder(Protocol):
    model: str  # stored per chunk in protocol_chunks.embedding_model

    def embed(self, texts: Sequence[str], *, task: EmbedTask) -> list[list[float]]:
        """One vector of EMBEDDING_DIMENSIONS floats per text, in order. Raises ProviderError."""
        ...
