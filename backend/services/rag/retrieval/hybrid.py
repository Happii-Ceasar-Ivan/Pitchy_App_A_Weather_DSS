"""Hybrid retrieval over approved protocol chunks (B5 plan 4.3): cosine + full-text, merged
with reciprocal-rank fusion. Read-only, so it runs as the least-privilege app login."""

from collections.abc import Callable
from dataclasses import dataclass
from typing import Literal

import psycopg

from services.rag.embeddings.vectors import vector_literal

CANDIDATES = 8
RRF_K = 60

RetrievalMode = Literal["hybrid", "keyword_only", "none"]

_COLUMNS = """c.id, d.document_key, d.title, d.authority, d.version, c.section, c.content,
  c.position"""
_FROM = """from public.protocol_chunks c
  join public.protocol_documents d on d.id = c.document_id
  where d.approval_status = 'approved'"""

_VECTOR_SQL = f"""select {_COLUMNS} {_FROM} and c.embedding is not null
  order by c.embedding operator(extensions.<=>) %s::extensions.vector, c.id limit %s"""
_KEYWORD_SQL = f"""select {_COLUMNS} {_FROM}
  and c.fts @@ websearch_to_tsquery('english', %s)
  order by ts_rank(c.fts, websearch_to_tsquery('english', %s)) desc, c.id limit %s"""


@dataclass(frozen=True)
class RetrievedChunk:
    document_key: str
    title: str
    authority: str
    version: str
    section: str | None
    content: str
    position: int


@dataclass(frozen=True)
class RetrievalResult:
    chunks: list[RetrievedChunk]
    mode: RetrievalMode


def reciprocal_rank_fusion(rankings: list[list], k: int = RRF_K) -> list:
    """Merge ranked id lists: score = sum of 1/(k + rank), rank from 1."""
    scores: dict = {}
    for ranking in rankings:
        for rank, item in enumerate(ranking, start=1):
            scores[item] = scores.get(item, 0.0) + 1.0 / (k + rank)
    return sorted(scores, key=lambda item: -scores[item])


class HybridRetriever:
    def __init__(self, connect: Callable[[], psycopg.Connection]) -> None:
        self._connect = connect

    def search(
        self, question: str, query_vector: list[float] | None, k: int = 4
    ) -> RetrievalResult:
        with self._connect() as conn:
            keyword_rows = conn.execute(_KEYWORD_SQL, (question, question, CANDIDATES)).fetchall()
            vector_rows = (
                conn.execute(_VECTOR_SQL, (vector_literal(query_vector), CANDIDATES)).fetchall()
                if query_vector is not None
                else []
            )
        rows = {row[0]: row for row in [*vector_rows, *keyword_rows]}
        rankings = [[r[0] for r in vector_rows], [r[0] for r in keyword_rows]]
        ordered = reciprocal_rank_fusion([r for r in rankings if r])[:k]
        chunks = [RetrievedChunk(*rows[chunk_id][1:]) for chunk_id in ordered]
        if not chunks:
            return RetrievalResult([], "none")
        return RetrievalResult(chunks, "hybrid" if query_vector is not None else "keyword_only")
