"""Split section text into overlapping chunks (B5 plan 4.3). Pure functions, no I/O."""

import re

CHUNK_SIZE = 800
CHUNK_OVERLAP = 100

_SENTENCE_END = re.compile(r"(?<=[.!?])\s+")


def _atoms(text: str, limit: int) -> list[tuple[str, bool]]:
    """Pieces of at most ``limit`` characters, each flagged when a paragraph starts there.

    A paragraph is kept whole when it fits, else split into sentences, else into words.
    """
    atoms: list[tuple[str, bool]] = []
    for paragraph in re.split(r"\n\s*\n", text):
        paragraph = " ".join(paragraph.split())
        if not paragraph:
            continue
        pieces = [paragraph] if len(paragraph) <= limit else _SENTENCE_END.split(paragraph)
        first = True
        for piece in pieces:
            for part in _words_to_fit(piece, limit):
                atoms.append((part, first))
                first = False
    return atoms


def _words_to_fit(piece: str, limit: int) -> list[str]:
    if len(piece) <= limit:
        return [piece]
    parts: list[str] = []
    current = ""
    for word in piece.split(" "):
        word = word or " "
        while len(word) > limit:  # a single very long token
            if current:
                parts.append(current)
                current = ""
            parts.append(word[:limit])
            word = word[limit:]
        if current and len(current) + 1 + len(word) > limit:
            parts.append(current)
            current = word
        else:
            current = f"{current} {word}" if current else word
    if current:
        parts.append(current)
    return parts


def _tail(text: str, overlap: int) -> str:
    """The last ``overlap`` characters of ``text``, starting at a word boundary."""
    if overlap <= 0 or len(text) <= overlap:
        return text if overlap > 0 else ""
    tail = text[-overlap:]
    if not text[-overlap - 1].isspace():  # cut inside a word: drop the partial word
        _, _, tail = tail.partition(" ")
    return tail.strip()


def chunk_text(text: str, size: int = CHUNK_SIZE, overlap: int = CHUNK_OVERLAP) -> list[str]:
    """Chunks of about ``size`` characters; each starts with the last ~``overlap`` characters of
    the previous one. Splits at paragraph, then sentence, then word boundaries. Whitespace is
    normalised (paragraphs are joined by a blank line)."""
    if not 0 <= overlap < size:
        raise ValueError("overlap must be >= 0 and smaller than size")
    chunks: list[str] = []
    current = ""
    has_new = False  # current holds more than the overlap tail
    for atom, new_paragraph in _atoms(text, size - overlap):
        separator = "\n\n" if new_paragraph else " "
        if current and len(current) + len(separator) + len(atom) > size and has_new:
            chunks.append(current)
            current = _tail(current, overlap)
            has_new = False
        if current:
            current += (separator if has_new or new_paragraph else " ") + atom
        else:
            current = atom
        has_new = True
    if current and has_new:
        chunks.append(current)
    return chunks
