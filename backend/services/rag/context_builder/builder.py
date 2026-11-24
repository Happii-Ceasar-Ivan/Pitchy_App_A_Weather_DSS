"""Builds what the AI may use for one answer (B5 plan 4.4): the assessment facts [A] and the
retrieved approved chunks [D1]..[D4].

Everything here is deterministic. The facts are written from the B4 assessment only; the model
never sees anything else about the match. Text from outside sources (official alert titles,
document text, the user's question) is untrusted data: it is cleaned so it cannot fake our
delimiters or citation labels, and it is always presented as quoted data, never as instructions.
"""

import re
from dataclasses import dataclass, field
from datetime import UTC, datetime, timedelta, timezone

from api.schemas.assessment import HazardIndicator, SafetyAssessment
from api.schemas.common import GuidanceReference
from services.rag.retrieval.hybrid import RetrievalResult

FACTS_LABEL = "A"
MAX_CHUNK_CHARS = 900
MAX_ALERT_TITLE_CHARS = 200
MANILA = timezone(timedelta(hours=8), "Asia/Manila")  # fixed UTC+8, no daylight saving

_CONTROL = re.compile(r"[\x00-\x08\x0b-\x1f\x7f]")
_DELIMITERS = re.compile(r"<<<|>>>|[\[\]{}]")


def clean_untrusted(text: str, limit: int | None = None) -> str:
    """Plain, single-spaced text that cannot open or close a block or fake a [label]."""
    text = _DELIMITERS.sub(" ", _CONTROL.sub(" ", text))
    text = " ".join(text.split())
    if limit is not None and len(text) > limit:
        text = text[: limit - 1].rstrip() + "…"
    return text


@dataclass(frozen=True)
class DocumentBlock:
    label: str  # "D1".."D4"
    reference: GuidanceReference
    content: str


@dataclass(frozen=True)
class AnswerContext:
    facts: str
    documents: list[DocumentBlock]
    # hazard -> the level the engine gave (id, label), or None when it gave no level
    classifications: dict[str, tuple[str, str] | None]
    fact_references: list[GuidanceReference] = field(default_factory=list)

    @property
    def labels(self) -> set[str]:
        return {FACTS_LABEL, *(d.label for d in self.documents)}

    @property
    def grounding_text(self) -> str:
        """All text the answer may take numbers from."""
        return "\n".join([self.facts, *(d.content for d in self.documents)])

    def references_for(self, labels: set[str]) -> list[GuidanceReference]:
        """References built by the backend from the cited labels (never from the model)."""
        refs: list[GuidanceReference] = []
        if FACTS_LABEL in labels:
            refs.extend(self.fact_references)
        refs.extend(d.reference for d in self.documents if d.label in labels)
        unique: dict[tuple[str, str | None], GuidanceReference] = {}
        for ref in refs:
            unique.setdefault((ref.document_id, ref.section), ref)
        return list(unique.values())


def _time(value: datetime | None) -> str:
    if value is None:
        return "unknown"
    utc = value.astimezone(UTC)
    local = value.astimezone(MANILA)
    return f"{utc:%Y-%m-%d %H:%M} UTC ({local:%Y-%m-%d %H:%M} Manila time)"


def _number(value: float) -> str:
    return f"{value:.1f}"


def _hazard_lines(ind: HazardIndicator) -> list[str]:
    lines = [f"Hazard {ind.hazard.value}: data status {ind.status.value}."]
    if ind.indicator_value is not None:
        unit = f" {ind.indicator_unit}" if ind.indicator_unit else ""
        what = " (WBGT estimate from the forecast)" if ind.hazard.value == "heat" else ""
        lines.append(f"  Value: {_number(ind.indicator_value)}{unit}{what}.")
    if ind.level is not None:
        lines.append(f'  Level from the approved rules: "{ind.level.label}" (id {ind.level.id}).')
        lines.append(f"  What the rule says: {' '.join(ind.level.action.split())}")
        src = ind.level.source
        lines.append(f"  Rule source: {src.authority}, {src.title}, {src.section or src.version}.")
    else:
        lines.append("  Level: none. Pitchy gives no level for this hazard now.")
    if ind.decided_by:
        lines.append(f"  Who decides: {ind.decided_by}.")
    for value in ind.inputs:
        if value.value is not None:
            unit = f" {value.unit}" if value.unit else ""
            lines.append(f"  Input {value.parameter}: {value.value:g}{unit}.")
    providers = {(i.provenance.source_name, i.provenance.retrieved_at) for i in ind.inputs}
    for name, retrieved in sorted(providers, key=lambda p: (p[0], p[1] or datetime.min)):
        lines.append(f"  Data source: {name}, retrieved {_time(retrieved)}.")
    for notice in ind.notices:
        lines.append(f"  Notice ({notice.source.authority}): {' '.join(notice.text.split())}")
    for step in ind.procedure:
        lines.append(f"  Procedure: {step}")
    for lim in ind.limitations:
        lines.append(f"  Limitation: {lim.message}")
    return lines


def build_context(assessment: SafetyAssessment, retrieval: RetrievalResult) -> AnswerContext:
    match = assessment.match_context
    lines = [
        f"[{FACTS_LABEL}] Pitchy safety assessment (deterministic rules engine, not AI).",
        f"Assessed: {_time(assessment.assessed_at)}; "
        f"inputs checked {_time(assessment.checked_at)}.",
        "Rules: "
        + ("approved" if assessment.rules_approved else "DRAFT, not approved")
        + f" ({assessment.rule_version}).",
        f"Match: kickoff {_time(match.kickoff_at)}, venue {match.venue.name}, "
        f"age group {assessment.age_group.value}.",
    ]
    classifications: dict[str, tuple[str, str] | None] = {}
    fact_refs: list[GuidanceReference] = []
    for ind in assessment.indicators:
        lines.extend(_hazard_lines(ind))
        if ind.level is not None:
            classifications[ind.hazard.value] = (ind.level.id, ind.level.label)
            fact_refs.append(ind.level.source)
            fact_refs.extend(ind.level.also_supported_by)
        else:
            classifications[ind.hazard.value] = None
        fact_refs.extend(n.source for n in ind.notices)
    if assessment.official_notices:
        lines.append("Official notices (shown as issued; Pitchy does not grade them):")
        for n in assessment.official_notices:
            title = clean_untrusted(n.title, MAX_ALERT_TITLE_CHARS)
            lines.append(
                f'  {clean_untrusted(n.issuer, 80)} ({n.kind}): "{title}"; issued '
                f"{_time(n.issued_at)}, valid until {_time(n.valid_until)}."
            )
    else:
        lines.append("Official notices: none stored for this venue.")
    for lim in assessment.limitations:
        lines.append(f"Overall: {lim.message}")

    documents = [
        DocumentBlock(
            label=f"D{i}",
            reference=GuidanceReference(
                document_id=chunk.document_key,
                title=chunk.title,
                authority=chunk.authority,
                version=chunk.version,
                section=chunk.section,
            ),
            content=clean_untrusted(chunk.content, MAX_CHUNK_CHARS),
        )
        for i, chunk in enumerate(retrieval.chunks, start=1)
    ]
    return AnswerContext("\n".join(lines), documents, classifications, fact_refs)
