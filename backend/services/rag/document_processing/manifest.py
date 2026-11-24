"""Read the knowledge-base manifest and the local text files, and turn them into chunks."""

import re
from dataclasses import dataclass
from pathlib import Path

import yaml

from services.rag.document_processing.chunker import chunk_text

KNOWLEDGE_BASE_DIR = Path(__file__).resolve().parent.parent / "knowledge_base"
_SECTION_LINE = re.compile(r"^# section:[ \t]*(.+?)[ \t]*$", re.MULTILINE)
_KEY = re.compile(r"^[a-z0-9_]+$")


class KnowledgeBaseError(Exception):
    """The manifest or a text file is missing something or does not match."""


@dataclass(frozen=True)
class ManifestEntry:
    key: str
    title: str
    authority: str
    version: str
    source_uri: str
    file: str
    sections: tuple[str, ...]


@dataclass(frozen=True)
class PreparedChunk:
    position: int
    section: str
    content: str


def load_manifest(path: Path = KNOWLEDGE_BASE_DIR / "manifest.yaml") -> dict[str, ManifestEntry]:
    try:
        raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    except (OSError, yaml.YAMLError) as exc:
        raise KnowledgeBaseError(f"Cannot read manifest {path.name}: {type(exc).__name__}") from exc
    documents = (raw or {}).get("documents") if isinstance(raw, dict) else None
    if not isinstance(documents, dict) or not documents:
        raise KnowledgeBaseError("Manifest needs a non-empty 'documents' mapping.")
    entries = {}
    for key, item in documents.items():
        if not isinstance(key, str) or not _KEY.match(key) or not isinstance(item, dict):
            raise KnowledgeBaseError(f"Bad manifest entry: {key!r}")
        fields = {}
        for name in ("title", "authority", "version", "source_uri", "file"):
            value = item.get(name)
            if not isinstance(value, str) or not value.strip():
                raise KnowledgeBaseError(f"Manifest entry {key}: '{name}' is required.")
            fields[name] = value.strip()
        sections = item.get("sections")
        if (
            not isinstance(sections, list)
            or not sections
            or not all(isinstance(s, str) and s.strip() for s in sections)
            or len(set(sections)) != len(sections)
        ):
            raise KnowledgeBaseError(f"Manifest entry {key}: 'sections' must be a unique list.")
        entries[key] = ManifestEntry(key=key, sections=tuple(s.strip() for s in sections), **fields)
    return entries


def parse_sections(text: str) -> dict[str, str]:
    """Split a text file at ``# section: <name>`` lines. Text before the first one is ignored
    only if blank; duplicate names are an error."""
    matches = list(_SECTION_LINE.finditer(text))
    if text[: matches[0].start() if matches else len(text)].strip():
        raise KnowledgeBaseError("Text before the first '# section:' line.")
    sections: dict[str, str] = {}
    for i, match in enumerate(matches):
        end = matches[i + 1].start() if i + 1 < len(matches) else len(text)
        name = match.group(1)
        if name in sections:
            raise KnowledgeBaseError(f"Duplicate section {name!r}.")
        sections[name] = text[match.end() : end].strip()
    return sections


def prepare_chunks(entry: ManifestEntry, text: str) -> list[PreparedChunk]:
    """Validate ``text`` against the manifest entry and chunk it, in manifest section order."""
    sections = parse_sections(text)
    unknown = [name for name in sections if name not in entry.sections]
    if unknown:
        raise KnowledgeBaseError(f"{entry.key}: unknown section(s) {unknown}.")
    missing = [name for name in entry.sections if not sections.get(name)]
    if missing:
        raise KnowledgeBaseError(f"{entry.key}: missing or empty section(s) {missing}.")
    chunks: list[PreparedChunk] = []
    for name in entry.sections:
        for content in chunk_text(sections[name]):
            chunks.append(PreparedChunk(position=len(chunks), section=name, content=content))
    return chunks


def read_document(
    entry: ManifestEntry, directory: Path = KNOWLEDGE_BASE_DIR
) -> list[PreparedChunk]:
    path = directory / entry.file
    if not path.is_file():
        raise KnowledgeBaseError(f"{entry.key}: text file {entry.file} is missing.")
    return prepare_chunks(entry, path.read_text(encoding="utf-8"))
