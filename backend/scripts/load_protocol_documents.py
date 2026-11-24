"""Load the RAG knowledge base (text files + manifest) into the database (B5 plan 4.3).

Run from ``backend/`` on the PC, like migrations::

    uv run python scripts/load_protocol_documents.py --dry-run     # parse and chunk, no DB
    uv run python scripts/load_protocol_documents.py               # load as 'draft'
    uv run python scripts/load_protocol_documents.py --approve     # load and mark 'approved'
    uv run python scripts/load_protocol_documents.py --only fifa_ecm_2022

Uses ``SUPABASE_DB_URL`` (admin) from the root ``.env``; the URL is never printed. Embeds with the
configured Gemini embedder. Each document is replaced in one transaction.
"""

import argparse
import sys
from collections.abc import Callable, Mapping, Sequence
from pathlib import Path

import psycopg

BACKEND_DIR = Path(__file__).resolve().parent.parent
if str(BACKEND_DIR) not in sys.path:  # allow `python scripts/load_protocol_documents.py`
    sys.path.insert(0, str(BACKEND_DIR))

from services.ai_providers.base import Embedder, ProviderError  # noqa: E402
from services.rag.document_processing.manifest import (  # noqa: E402
    KNOWLEDGE_BASE_DIR,
    KnowledgeBaseError,
    ManifestEntry,
    PreparedChunk,
    load_manifest,
    read_document,
)
from services.rag.embeddings.vectors import embed_documents, vector_literal  # noqa: E402

_UPSERT_DOCUMENT = """
insert into public.protocol_documents
  (document_key, title, authority, version, source_uri, approval_status, reviewed_at)
values (%(key)s, %(title)s, %(authority)s, %(version)s, %(source_uri)s, %(status)s,
        case when %(status)s = 'approved' then now() end)
on conflict (document_key) do update set
  title = excluded.title, authority = excluded.authority, version = excluded.version,
  source_uri = excluded.source_uri, approval_status = excluded.approval_status,
  reviewed_at = excluded.reviewed_at
returning id
"""
_INSERT_CHUNK = """
insert into public.protocol_chunks
  (document_id, position, section, content, embedding, embedding_model)
values (%s, %s, %s, %s, %s::extensions.vector, %s)
"""


def select_entries(manifest: Mapping[str, ManifestEntry], only: str | None) -> list[ManifestEntry]:
    if only is None:
        return list(manifest.values())
    if only not in manifest:
        raise KnowledgeBaseError(f"--only: unknown document key {only!r}.")
    return [manifest[only]]


def load_document(
    conn: psycopg.Connection,
    entry: ManifestEntry,
    chunks: Sequence[PreparedChunk],
    embedder: Embedder,
    *,
    approve: bool,
) -> int:
    """Replace one document and its chunks in a single transaction. Returns the chunk count."""
    vectors = embed_documents(embedder, [c.content for c in chunks])  # before touching the DB
    with conn.transaction():
        params = {
            "key": entry.key,
            "title": entry.title,
            "authority": entry.authority,
            "version": entry.version,
            "source_uri": entry.source_uri,
            "status": "approved" if approve else "draft",
        }
        document_id = conn.execute(_UPSERT_DOCUMENT, params).fetchone()[0]
        conn.execute("delete from public.protocol_chunks where document_id = %s", (document_id,))
        for chunk, vector in zip(chunks, vectors, strict=True):
            conn.execute(
                _INSERT_CHUNK,
                (
                    document_id,
                    chunk.position,
                    chunk.section,
                    chunk.content,
                    vector_literal(vector),
                    embedder.model,
                ),
            )
    return len(chunks)


def load(
    conn: psycopg.Connection,
    embedder: Embedder,
    *,
    approve: bool = False,
    only: str | None = None,
    manifest: Mapping[str, ManifestEntry] | None = None,
    directory: Path = KNOWLEDGE_BASE_DIR,
    report: Callable[[str], None] = print,
) -> dict[str, int]:
    """Read, validate and load every selected document. All files are validated before any is
    loaded, so a bad file stops the run before the database changes."""
    manifest = load_manifest(directory / "manifest.yaml") if manifest is None else manifest
    prepared = [(e, read_document(e, directory)) for e in select_entries(manifest, only)]
    counts = {}
    for entry, chunks in prepared:
        counts[entry.key] = load_document(conn, entry, chunks, embedder, approve=approve)
        report(
            f"{entry.key}: {counts[entry.key]} chunks loaded ({'approved' if approve else 'draft'})"
        )
    return counts


def dry_run(
    only: str | None = None,
    manifest: Mapping[str, ManifestEntry] | None = None,
    directory: Path = KNOWLEDGE_BASE_DIR,
    report: Callable[[str], None] = print,
) -> dict[str, int]:
    manifest = load_manifest(directory / "manifest.yaml") if manifest is None else manifest
    counts = {}
    for entry in select_entries(manifest, only):
        chunks = read_document(entry, directory)
        counts[entry.key] = len(chunks)
        sections = len({c.section for c in chunks})
        report(f"{entry.key}: {len(chunks)} chunks in {sections} section(s) (dry run)")
    return counts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--approve", action="store_true", help="mark loaded documents approved")
    parser.add_argument(
        "--dry-run", action="store_true", help="parse and count; no embedding, no DB"
    )
    parser.add_argument("--only", metavar="KEY", help="load one document key only")
    args = parser.parse_args()

    try:
        if args.dry_run:
            dry_run(args.only)
            return 0

        from services.ai_providers.factory import build_embedder
        from shared.settings import Settings

        settings = Settings()
        url = settings.supabase_db_url.get_secret_value() if settings.supabase_db_url else None
        if not url:
            print("SUPABASE_DB_URL is not set (see the root .env).", file=sys.stderr)
            return 2
        embedder = build_embedder(settings)
        with psycopg.connect(url, autocommit=True, connect_timeout=15) as conn:
            load(conn, embedder, approve=args.approve, only=args.only)
    except KnowledgeBaseError as exc:
        print(f"Knowledge base problem: {exc}", file=sys.stderr)
        return 1
    except ProviderError as exc:
        print(f"Embedding failed: {exc.code}", file=sys.stderr)
        return 1
    except psycopg.OperationalError as exc:
        print(f"Could not connect or write: {str(exc).splitlines()[0][:120]}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
