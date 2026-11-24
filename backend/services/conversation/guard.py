"""Deterministic answer check (B5 plan 4.5): the safety net between the model and the user.

A reply is rejected (the router then tries the next provider) unless all of these hold:
1. It is JSON {"answer": str, "sources": [str]}; the answer is non-empty and not too long.
2. Every cited label ([A], [D1].., and the sources list) exists in what the model was given.
3. Every number with a unit (°C, km, minutes, %, ...) appears in the facts or the documents,
   allowing rounding. This blocks invented measurements and thresholds.
4. No level label or id from rules.yaml appears unless it is the level the engine gave for that
   hazard; no wording that claims a level the engine did not give; never "it is safe".
HTML, links and markdown are removed first, so the answer is returned as plain text.

This check is strict on purpose: a rejected answer costs only a fallback or an "unavailable"
reply; the deterministic assessment is always shown by the app.
"""

import json
import re
from dataclasses import dataclass, field

from services.rag.context_builder.builder import AnswerContext
from services.safety_engine.rules import RuleSet

MAX_ANSWER_CHARS = 1500

_FENCE = re.compile(r"^\s*```(?:json)?\s*|\s*```\s*$", re.IGNORECASE)
_TAG = re.compile(r"<[^>]{0,200}>")
_MD_LINK = re.compile(r"\[([^\]\n]{1,200})\]\((?:[^)\s]{1,500})\)")
_URL = re.compile(r"\b(?:https?://|www\.)\S+", re.IGNORECASE)
_MD_MARKS = re.compile(r"\*\*|__|`+|^\s{0,3}#{1,6}\s+|^\s*>\s?", re.MULTILINE)
_LABEL = re.compile(r"\[(A|D\d{1,2})\]")
_UNIT = (
    r"(?:°\s?[CF]\b|º\s?[CF]\b|degrees?(?:\s+(?:celsius|fahrenheit|c|f))?\b|celsius\b"
    r"|km\b|kilomet(?:er|re)s?\b|metres?\b|meters?\b|m\b"
    r"|min(?:ute)?s?\b|hours?\b|hrs?\b|seconds?\b|secs?\b|s\b"
    r"|%|per\s?cent\b|mm(?:/h)?\b|millimet(?:er|re)s?\b|hpa\b|m/s\b|km/h\b)"
)
_NUMBER_WITH_UNIT = re.compile(rf"(?<![\w.])(\d+(?:[.,]\d+)?)\s?(?:-\s?)?{_UNIT}", re.IGNORECASE)
_ANY_NUMBER = re.compile(r"\d+(?:[.,]\d+)?")
_NEGATION = re.compile(r"\b(?:not|no|never|nor|without|cannot|isn't|aren't|n't)\b", re.I)

# Claims that conditions are safe: never allowed (unless negated, e.g. "not a statement that it
# is safe", which the rules themselves use).
_SAFE_CLAIMS = [
    re.compile(
        r"\b(?:conditions?|it|play|playing|the match|the game|the pitch|weather|everything)"
        r"\s+(?:is|are|looks?|seems?|will be)\s+(?:completely\s+|perfectly\s+|totally\s+)?safe\b",
        re.I,
    ),
    re.compile(r"\bsafe\s+to\s+(?:play|continue|proceed|start|train)\b", re.I),
    re.compile(r"\b(?:no|zero)\s+(?:heat\s+|lightning\s+)?(?:risk|danger)\b", re.I),
]
# Wording that claims a level, per hazard: (level id that allows it, pattern). Shown only when the
# engine gave that level; otherwise rejected unless negated.
_LEVEL_CLAIMS = [
    (
        "heat",
        "cooling_breaks_required",
        re.compile(
            r"\bcooling\s+breaks?\s+(?:are|is|will be)\s+(?:now\s+)?"
            r"(?:required|mandatory|needed|necessary|compulsory)\b"
            r"|\b(?:must|need to|have to|should)\s+(?:use|take|have|hold)\s+cooling\s+breaks?\b",
            re.I,
        ),
    ),
    (
        "lightning",
        "within_30_second_distance",
        re.compile(
            r"\blightning\s+(?:is\s+|was\s+|has been\s+)?(?:detected\s+|seen\s+)?within\s+"
            r"(?:about\s+|around\s+|roughly\s+)?10\s?(?:km|kilomet)",
            re.I,
        ),
    ),
]


# Wording that denies the level the engine gave: rejected when that level is the one given.
_DENIALS = [
    (
        "heat",
        "cooling_breaks_required",
        re.compile(
            r"\bcooling\s+breaks?\s+(?:are|is)\s+not\s+(?:required|needed|necessary|mandatory)"
            r"|\bno\s+(?:need\s+for\s+)?cooling\s+breaks?\b"
            r"|\bbelow\s+the\s+(?:youth\s+)?cooling[-\s]break\s+level\b",
            re.I,
        ),
    ),
    (
        "lightning",
        "within_30_second_distance",
        re.compile(
            r"\bno\s+lightning\b|\blightning\s+(?:is|was)\s+not\s+(?:detected|within)"
            r"|\bnot\s+within\s+(?:about\s+)?10\s?km",
            re.I,
        ),
    ),
]


@dataclass(frozen=True)
class GuardResult:
    ok: bool
    reason: str  # "OK" or the first failed check (never shown to users)
    answer: str | None = None
    cited: set[str] = field(default_factory=set)


def _reject(reason: str) -> GuardResult:
    return GuardResult(False, reason)


def _plain(text: str) -> str:
    text = _MD_LINK.sub(r"\1", text)
    text = _TAG.sub(" ", text)
    text = _URL.sub(" ", text)
    text = _MD_MARKS.sub("", text)
    lines = [" ".join(line.split()) for line in text.splitlines()]
    return "\n".join(line for line in lines if line).strip()


def _parse(raw: str) -> tuple[str, list[str]] | None:
    text = _FENCE.sub("", raw.strip())
    try:
        data = json.loads(text)
    except ValueError:
        start, end = text.find("{"), text.rfind("}")
        if start < 0 or end <= start:
            return None
        try:
            data = json.loads(text[start : end + 1])
        except ValueError:
            return None
    if not isinstance(data, dict) or not isinstance(data.get("answer"), str):
        return None
    sources = data.get("sources", [])
    if not isinstance(sources, list) or not all(isinstance(s, str) for s in sources):
        return None
    return data["answer"], [s.strip().strip("[]") for s in sources]


def _to_float(token: str) -> float:
    return float(token.replace(",", "."))


def _allowed(value: float, grounded: set[float]) -> bool:
    for g in grounded:
        if abs(g - value) < 1e-9 or round(g) == value or round(g, 1) == value:
            return True
    return False


def _negated(text: str, start: int) -> bool:
    """A negation shortly before the match, in the same clause ("No flash, so it is safe" is
    not negated; "not a statement that it is safe" is)."""
    window = re.split(r"[.!?;:,\n]|\bso\b|\bbut\b", text[max(0, start - 40) : start])[-1]
    return _NEGATION.search(window) is not None


def _unnegated_match(pattern: re.Pattern, text: str) -> bool:
    return any(not _negated(text, m.start()) for m in pattern.finditer(text))


def _norm(text: str) -> str:
    return " ".join(text.lower().split())


def level_catalogue(rules: RuleSet) -> dict[str, list[tuple[str, str]]]:
    """Every (level id, label) in the rules, per hazard."""
    heat = [(lv.id, lv.label) for ls in rules.hazards.heat.level_sets for lv in ls.levels]
    distance = getattr(rules.hazards.lightning, "distance_levels", [])
    lightning = [(lv.id, lv.label) for lv in distance]
    return {"heat": heat, "lightning": lightning}


def check_answer(raw: str, context: AnswerContext, rules: RuleSet) -> GuardResult:
    parsed = _parse(raw)
    if parsed is None:
        return _reject("NOT_JSON")
    answer, sources = parsed
    answer = _plain(answer)
    if not answer:
        return _reject("EMPTY")
    if len(answer) > MAX_ANSWER_CHARS:
        return _reject("TOO_LONG")

    cited = set(_LABEL.findall(answer)) | {s for s in sources if s}
    if not cited <= context.labels:
        return _reject("UNKNOWN_CITATION")

    lowered = _norm(answer)
    for hazard, levels in level_catalogue(rules).items():
        given = context.classifications.get(hazard)
        for level_id, label in levels:
            same_id = given is not None and level_id == given[0]
            if same_id and _norm(label) == _norm(given[1]):
                continue  # the engine's own level, in its own words
            if _norm(label) in lowered or (not same_id and level_id in lowered):
                return _reject("LEVEL_NOT_GIVEN")
    for hazard, level_id, pattern in _LEVEL_CLAIMS:
        given = context.classifications.get(hazard)
        if (given is None or given[0] != level_id) and _unnegated_match(pattern, answer):
            return _reject("LEVEL_NOT_GIVEN")
    for hazard, level_id, pattern in _DENIALS:
        given = context.classifications.get(hazard)
        if given is not None and given[0] == level_id and pattern.search(answer):
            return _reject("LEVEL_DENIED")
    if any(_unnegated_match(p, answer) for p in _SAFE_CLAIMS):
        return _reject("SAFETY_CLAIM")

    grounded = {_to_float(t) for t in _ANY_NUMBER.findall(context.grounding_text)}
    for match in _NUMBER_WITH_UNIT.finditer(answer):
        if not _allowed(_to_float(match.group(1)), grounded):
            return _reject("UNGROUNDED_NUMBER")

    return GuardResult(True, "OK", answer, cited)
