import psycopg
import pytest

from scripts.load_protocol_documents import dry_run, load
from services.ai_providers.base import EMBEDDING_DIMENSIONS
from services.rag.document_processing.manifest import KnowledgeBaseError
from services.rag.retrieval.hybrid import HybridRetriever, reciprocal_rank_fusion
from tests.conftest import requires_db

MANIFEST_YAML = """
documents:
  doc_a:
    title: Doc A
    authority: Authority A
    version: "1"
    source_uri: ref-a
    file: doc_a.txt
    sections: [Heat, Lightning]
  doc_b:
    title: Doc B
    authority: Authority B
    version: "2"
    source_uri: ref-b
    file: doc_b.txt
    sections: [Whole]
"""


def vec(*hot: int) -> list[float]:
    v = [0.0] * EMBEDDING_DIMENSIONS
    for i in hot:
        v[i] = 1.0
    return v


class FakeEmbedder:
    model = "fake-embed-1"

    def __init__(self):
        self.calls = []

    def embed(self, texts, *, task):
        self.calls.append((len(texts), task))
        return [vec(0) for _ in texts]


@pytest.fixture
def kb(tmp_path):
    (tmp_path / "manifest.yaml").write_text(MANIFEST_YAML, encoding="utf-8")
    (tmp_path / "doc_a.txt").write_text(
        "# section: Heat\nCooling breaks are taken when the heat index is high.\n"
        "# section: Lightning\nSuspend play when lightning is detected nearby.\n",
        encoding="utf-8",
    )
    (tmp_path / "doc_b.txt").write_text(
        "# section: Whole\nHydration advice for hot afternoons.\n", encoding="utf-8"
    )
    return tmp_path


def test_dry_run_counts_without_db(kb):
    lines = []
    counts = dry_run(directory=kb, report=lines.append)
    assert counts == {"doc_a": 2, "doc_b": 1}
    assert len(lines) == 2


def test_missing_file_and_unknown_only(kb):
    (kb / "doc_b.txt").unlink()
    with pytest.raises(KnowledgeBaseError):
        dry_run(directory=kb)
    with pytest.raises(KnowledgeBaseError):
        dry_run(only="nope", directory=kb)
    assert dry_run(only="doc_a", directory=kb) == {"doc_a": 2}


@requires_db
def test_loader_upserts_replaces_and_approves(conn, kb):
    embedder = FakeEmbedder()
    load(conn, embedder, directory=kb, report=lambda _: None)
    rows = conn.execute(
        "select document_key, approval_status, reviewed_at from public.protocol_documents"
        " order by 1"
    ).fetchall()
    assert [(r[0], r[1], r[2]) for r in rows] == [
        ("doc_a", "draft", None),
        ("doc_b", "draft", None),
    ]
    assert embedder.calls and all(task == "document" for _, task in embedder.calls)
    chunk_rows = conn.execute(
        "select c.position, c.section, c.embedding_model, c.embedding is not null"
        " from public.protocol_chunks c join public.protocol_documents d on d.id = c.document_id"
        " where d.document_key = 'doc_a' order by c.position"
    ).fetchall()
    assert chunk_rows == [
        (0, "Heat", "fake-embed-1", True),
        (1, "Lightning", "fake-embed-1", True),
    ]
    first_id = conn.execute(
        "select id from public.protocol_documents where document_key = 'doc_a'"
    ).fetchone()[0]

    # re-load with changed text and --approve: same document row, chunks replaced
    (kb / "doc_a.txt").write_text(
        "# section: Heat\nNew heat text only.\n# section: Lightning\nNew lightning text.\n",
        encoding="utf-8",
    )
    load(conn, embedder, approve=True, only="doc_a", directory=kb, report=lambda _: None)
    row = conn.execute(
        "select id, approval_status, reviewed_at is not null from public.protocol_documents"
        " where document_key = 'doc_a'"
    ).fetchone()
    assert row == (first_id, "approved", True)
    contents = conn.execute(
        "select content from public.protocol_chunks where document_id = %s order by position",
        (first_id,),
    ).fetchall()
    assert contents == [("New heat text only.",), ("New lightning text.",)]
    assert (
        conn.execute(
            "select approval_status from public.protocol_documents where document_key = 'doc_b'"
        ).fetchone()[0]
        == "draft"
    )


@requires_db
def test_failed_embedding_leaves_database_unchanged(conn, kb):
    class Broken(FakeEmbedder):
        def embed(self, texts, *, task):
            raise ValueError("boom")

    with pytest.raises(ValueError):
        load(conn, Broken(), directory=kb, report=lambda _: None)
    assert conn.execute("select count(*) from public.protocol_documents").fetchone()[0] == 0


def test_rrf_order():
    assert reciprocal_rank_fusion([["a", "b", "c"], ["c", "a"]]) == ["a", "c", "b"]
    assert reciprocal_rank_fusion([[], []]) == []


def add_doc(conn, key, status, chunks):
    doc_id = conn.execute(
        "insert into public.protocol_documents (document_key, title, authority, version,"
        " approval_status) values (%s, %s, 'Auth', '1', %s) returning id",
        (key, f"Title {key}", status),
    ).fetchone()[0]
    for position, (content, vector) in enumerate(chunks):
        literal = "[" + ",".join(str(x) for x in vector) + "]" if vector else None
        conn.execute(
            "insert into public.protocol_chunks (document_id, position, section, content,"
            " embedding, embedding_model) values (%s, %s, 'S', %s, %s::extensions.vector, %s)",
            (doc_id, position, content, literal, "fake" if vector else None),
        )


@pytest.fixture
def retriever(conn, connect):
    add_doc(
        conn,
        "approved_doc",
        "approved",
        [
            ("lightning storm suspend play", vec(2)),  # chunk 0: keyword match, vector far
            ("water bottles and shade", vec(0)),  # chunk 1: vector match only
            ("lightning delay thirty minutes after the last strike", vec(0, 1)),  # both
            ("unrelated referee uniform rules", None),
        ],
    )
    add_doc(conn, "draft_doc", "draft", [("lightning draft secret text", vec(0))])
    add_doc(conn, "retired_doc", "retired", [("lightning retired secret text", vec(0))])
    return HybridRetriever(connect)


@requires_db
def test_hybrid_ranking_merges_both_lists(retriever):
    result = retriever.search("lightning", vec(0, 1), k=4)
    assert result.mode == "hybrid"
    contents = [c.content for c in result.chunks]
    # chunk 2 is in both lists, so it wins; the others follow
    assert contents[0].startswith("lightning delay")
    assert set(contents[:3]) == {
        "lightning delay thirty minutes after the last strike",
        "water bottles and shade",
        "lightning storm suspend play",
    }
    first = result.chunks[0]
    assert (first.document_key, first.title, first.authority, first.version) == (
        "approved_doc",
        "Title approved_doc",
        "Auth",
        "1",
    )
    assert first.section == "S" and first.position == 2


@requires_db
def test_k_limits_results(retriever):
    assert len(retriever.search("lightning", vec(0), k=2).chunks) == 2


@requires_db
def test_keyword_only_when_no_vector(retriever):
    result = retriever.search("lightning", None)
    assert result.mode == "keyword_only"
    assert {c.position for c in result.chunks} == {0, 2}


@requires_db
def test_draft_and_retired_never_returned(retriever):
    for vector in (None, vec(0)):
        result = retriever.search("lightning secret draft retired", vector, k=8)
        assert all(c.document_key == "approved_doc" for c in result.chunks)
        assert not any("secret" in c.content for c in result.chunks)


@requires_db
def test_none_when_nothing_matches(retriever):
    assert retriever.search("zzzqqq", None).mode == "none"
    assert retriever.search("zzzqqq", None).chunks == []


@requires_db
def test_empty_database_and_empty_question(conn, connect):
    retriever = HybridRetriever(connect)
    assert retriever.search("lightning", vec(0)).mode == "none"
    assert retriever.search("", None).mode == "none"


@requires_db
def test_sql_looking_question_is_harmless(retriever, conn):
    question = "'; drop table public.protocol_chunks; --"
    result = retriever.search(question, None)
    assert result.mode == "none"
    assert conn.execute("select count(*) from public.protocol_chunks").fetchone()[0] == 6


@requires_db
def test_retriever_runs_as_least_privilege_login(retriever, connect):
    with connect() as c, pytest.raises(psycopg.errors.InsufficientPrivilege):
        c.execute("delete from public.protocol_chunks")
    assert retriever.search("lightning", None).chunks
