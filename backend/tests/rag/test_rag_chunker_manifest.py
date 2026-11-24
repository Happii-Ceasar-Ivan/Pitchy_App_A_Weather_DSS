import pytest
import yaml

from services.rag.document_processing.chunker import chunk_text
from services.rag.document_processing.manifest import (
    KNOWLEDGE_BASE_DIR,
    KnowledgeBaseError,
    ManifestEntry,
    load_manifest,
    parse_sections,
    prepare_chunks,
)

SENTENCE = "Stop play when lightning is seen within the agreed distance. "


def test_short_text_is_one_chunk_and_whitespace_is_normalised():
    assert chunk_text("  Hello \n  world.\t\n\n\n Second   paragraph. ") == [
        "Hello world.\n\nSecond paragraph."
    ]


def test_empty_text_gives_no_chunks():
    assert chunk_text(" \n\n ") == []


def test_chunks_are_about_800_with_overlap_and_cover_everything():
    text = " ".join(f"Sentence number {i} says to stop play for safety." for i in range(60))
    chunks = chunk_text(text)
    assert len(chunks) > 3
    assert all(len(c) <= 800 for c in chunks)
    assert all(len(c) > 400 for c in chunks[:-1])
    for previous, nxt in zip(chunks, chunks[1:], strict=False):
        # the next chunk starts with the last ~100 characters of the previous one
        overlap = max(n for n in range(len(nxt) + 1) if previous.endswith(nxt[:n]))
        assert 40 <= overlap <= 100
    assert chunks[0].startswith("Sentence number 0")
    assert chunks[-1].endswith("number 59 says to stop play for safety.")


def test_splits_at_paragraph_boundaries_first():
    paragraphs = [(f"Paragraph {i}. " + "word " * 70).strip() for i in range(6)]
    chunks = chunk_text("\n\n".join(paragraphs))
    for chunk in chunks:
        for part in chunk.split("\n\n"):
            # every non-first part is a whole paragraph or an overlap tail followed by one
            assert part.endswith("word")


def test_sentences_stay_whole_when_they_fit():
    chunks = chunk_text((SENTENCE * 40).strip())
    assert all(c.endswith(".") for c in chunks)


def test_very_long_token_is_hard_split():
    chunks = chunk_text("x" * 2000)
    assert all(len(c) <= 800 for c in chunks)
    assert len(chunks) >= 3


def test_bad_overlap_rejected():
    with pytest.raises(ValueError):
        chunk_text("abc", size=100, overlap=100)


ENTRY = ManifestEntry(
    key="doc_a",
    title="T",
    authority="A",
    version="1",
    source_uri="u",
    file="doc_a.txt",
    sections=("One", "Two"),
)


def test_parse_sections():
    text = "# section: One\nfirst body\n\n# section:Two  \nsecond body\n"
    assert parse_sections(text) == {"One": "first body", "Two": "second body"}


def test_prepare_chunks_never_cross_sections_and_positions_are_sequential():
    text = f"# section: One\n{(SENTENCE * 40).strip()}\n# section: Two\n{(SENTENCE * 40).strip()}"
    chunks = prepare_chunks(ENTRY, text)
    assert [c.position for c in chunks] == list(range(len(chunks)))
    assert {c.section for c in chunks} == {"One", "Two"}
    sections_in_order = [c.section for c in chunks]
    assert sections_in_order == sorted(sections_in_order)  # all "One" chunks, then all "Two"


@pytest.mark.parametrize(
    "text",
    [
        "# section: One\nbody",  # lacks Two
        "# section: One\nbody\n# section: Two\n\n",  # Two empty
        "# section: One\nb\n# section: Two\nb\n# section: Three\nb",  # unknown
        "# section: One\nb\n# section: One\nb\n# section: Two\nb",  # duplicate
        "stray text\n# section: One\nb\n# section: Two\nb",  # text before first section
        "no sections at all",
    ],
)
def test_prepare_chunks_rejects_bad_files(text):
    with pytest.raises(KnowledgeBaseError):
        prepare_chunks(ENTRY, text)


def test_committed_manifest_is_valid_and_matches_rules_yaml_sources():
    manifest = load_manifest()
    rules = yaml.safe_load(
        (KNOWLEDGE_BASE_DIR.parent.parent / "safety_engine/thresholds/rules.yaml").read_text(
            encoding="utf-8"
        )
    )
    assert set(manifest) == set(rules["sources"])
    for key, entry in manifest.items():
        source = rules["sources"][key]
        assert entry.version == source["version"]
        assert entry.authority == source["issuer"]
        assert entry.file == f"{key}.txt"


def test_manifest_errors(tmp_path):
    path = tmp_path / "m.yaml"
    path.write_text("documents:\n  Bad-Key:\n    title: x\n", encoding="utf-8")
    with pytest.raises(KnowledgeBaseError):
        load_manifest(path)
    path.write_text(
        "documents:\n  a:\n    title: x\n    authority: y\n    version: '1'\n"
        "    source_uri: u\n    file: a.txt\n    sections: []\n",
        encoding="utf-8",
    )
    with pytest.raises(KnowledgeBaseError):
        load_manifest(path)
    with pytest.raises(KnowledgeBaseError):
        load_manifest(tmp_path / "missing.yaml")
