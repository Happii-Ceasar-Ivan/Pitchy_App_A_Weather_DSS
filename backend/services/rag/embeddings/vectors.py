"""Embedding helpers shared by the loader and (later) the query side."""

from collections.abc import Sequence

from services.ai_providers.base import EMBEDDING_DIMENSIONS, Embedder

BATCH_SIZE = 32


def embed_documents(
    embedder: Embedder, texts: Sequence[str], batch_size: int = BATCH_SIZE
) -> list[list[float]]:
    """Embed ``texts`` in batches with task="document"; one vector per text, in order."""
    vectors: list[list[float]] = []
    for start in range(0, len(texts), batch_size):
        batch = list(texts[start : start + batch_size])
        result = embedder.embed(batch, task="document")
        if len(result) != len(batch) or any(len(v) != EMBEDDING_DIMENSIONS for v in result):
            raise ValueError("Embedder returned the wrong number or size of vectors.")
        vectors.extend(result)
    return vectors


def vector_literal(vector: Sequence[float]) -> str:
    """pgvector text form: ``[x,y,...]``."""
    return "[" + ",".join(repr(float(x)) for x in vector) + "]"
