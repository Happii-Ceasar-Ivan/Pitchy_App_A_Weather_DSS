"""Deterministic answer check (B5 plan 4.5): the safety net between the model and the user.

A reply is rejected (the router then tries the next provider) unless all of these hold:
1. It is JSON {"answer": str, "sources": [str]}; the answer is non-empty and not too long.
   {"off_topic": true} is accepted as a decline: the route then shows Pitchy's fixed message,
   so the model never writes a reply of its own to an off-topic question.
2. It cites at least one block, and every cited label ([A], [D1].., and the sources list)
   exists in what the model was given. An answer that cites nothing (a poem, code, a recipe)
   is rejected.
3. Every number with a unit (°C, km, minutes, %, ...) appears in the facts or the documents,
   allowing rounding. This blocks invented measurements and thresholds. One exception (P-21):
   a number from the user's own question, where the answer says in the same clause that it is
   the user's ("the 35 °C you mentioned", "your 35 °C").
4. No level label or id from rules.yaml appears unless it is the level the engine gave for that
   hazard; no wording that claims a level the engine did not give; never "it is safe".
   Without a match (``context.general``): a [D] block must be cited, level wording only in a
   sentence that cites a document, numbers only from the cited documents, nothing about current
   conditions ("today", "now", "this match").
HTML, links and markdown are removed first, so the answer is returned as plain text.
Answers are in English (P-21); a few Filipino/Taglish "it is safe" phrases are a backup.

This check is strict on purpose: a rejected answer costs only a fallback or an "unavailable"
reply; the deterministic assessment is always shown by the app.
"""

import json
import re
import unicodedata
from dataclasses import dataclass, field

from services.rag.context_builder.builder import AnswerContext
from services.safety_engine.rules import RuleSet

MAX_ANSWER_CHARS = 1500

# Look-alike dashes and spaces (seen live: "cooling‑break"). NFKC turns most look-alikes,
# such as non-breaking spaces, into plain ones; these dashes are then mapped to "-", so the
# checks below cannot be dodged by a different hyphen.
_DASHES = dict.fromkeys(map(ord, "‐‑‒–—―−﹘﹣－"), "-")
_APOSTROPHES = dict.fromkeys(map(ord, "‘’‛ʼ′"), "'")  # "isn’t" is checked as "isn't"


def _canon(text: str) -> str:
    return unicodedata.normalize("NFKC", text).translate(_DASHES).translate(_APOSTROPHES)


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
# A negation cancels a claim only when it is one of the few words right before it, in the same
# clause (B6): "It is not raining and the match is safe" is a claim; "not a statement that it is
# safe" is not. "no", "nor" and "without" don't count ("No rain today the match is safe").
_NEGATION = re.compile(r"\b(?:not|never|cannot|hindi|di)\b|\b\w+n't\b", re.I)
_CLAUSE_BREAK = re.compile(
    r"[.!?;:,()\n]|\s-\s|\b(?:so|but|and|or|while|although|though|because|then|however|yet)\b",
    re.I,
)
NEGATION_WORDS = 4
# The user's own number, said to be theirs in the same clause (P-21). "your" counts only right
# before the number ("your team stops at 35 °C" is not the user's number); after "you
# mentioned" etc. only a few filler words may come between.
_ATTRIBUTED_BEFORE = re.compile(
    r"(?:\byour|\byou(?:'ve|\s+have)?\s+(?:mentioned|asked(?:\s+(?:about|if|whether))?|gave|said"
    r"|quoted|wrote|suggested)(?:\s+(?:a|an|the|of|about|whether|if|wbgt|temperature|heat"
    r"|index|value|reading|figure|number)){0,3})\s+$",
    re.I,
)
# An attributed number is still rejected when its clause makes a threshold or decision claim
# about it ("the 40 °C you mentioned is the limit"): only the engine classifies (P-21).
_JUDGEMENT = re.compile(
    r"\b(?:limit|threshold|cut-?off|level|maximum|max|minimum|stop|stops|cancel|suspend|postpone"
    r"|above|below|over|under|exceed\w*|too|dangerous|danger|unsafe|safe|risk\w*|okay|ok|fine"
    r"|delikado|ligtas|mapanganib)\b",
    re.I,
)
_ATTRIBUTED_AFTER = re.compile(
    r"^\s+(?:that\s+)?you(?:'ve|\s+have)?\s+(?:mentioned|asked\s+about|gave|said|quoted|wrote"
    r"|suggested)\b",
    re.I,
)

# Claims that conditions are safe: never allowed (unless negated, e.g. "not a statement that it
# is safe", which the rules themselves use).
_SAFE_CLAIMS = [
    re.compile(
        r"\b(?:conditions?|it|that|play|playing|the match|the game|the pitch|weather|everything)"
        r"(?:\s+(?:is|are|looks?|seems?|will be)|'s|'re)\s+"
        r"(?:completely\s+|perfectly\s+|totally\s+|now\s+)?safe\b",
        re.I,
    ),
    re.compile(r"\bsafe\s+to\s+(?:play|continue|proceed|start|train|go\s+ahead)\b", re.I),
    re.compile(r"\b(?:no|zero)\s+(?:heat\s+|lightning\s+)?(?:risk|danger)\b", re.I),
    # Filipino / Taglish backup (P-21; to be reviewed by a Filipino speaker on the team).
    re.compile(
        r"\b(?:ligtas|safe)\s+(?:na\s+)?(?:po\s+)?(?:ang\s+|na\s+)?"
        r"(?:mag-?laro|maglaro|laro|laban|tumuloy|ituloy|panahon|kondisyon|lahat)\b",
        re.I,
    ),
    re.compile(r"\b(?:laro|laban|panahon|kondisyon|lahat)\s+(?:ay\s+)?(?:ligtas|safe)\b", re.I),
    re.compile(r"\bwalang\s+(?:panganib|peligro|delikado|risk|danger)\b", re.I),
    re.compile(r"\b(?:hindi|di)\s+(?:delikado|mapanganib)\b", re.I),
    re.compile(
        r"\b(?:pwede|puwede|pede)(?:ng)?\s+(?:na\s+|nang\s+)?(?:mag-?laro|maglaro|ituloy)\b", re.I
    ),
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


def _parse(raw: str) -> tuple[str, list[str]] | str | None:
    """(answer, sources), or "OFF_TOPIC" for the model's decline flag, or None if malformed."""
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
    if isinstance(data, dict) and data.get("off_topic") is True:
        return "OFF_TOPIC"
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
    """A negation among the last few words before the match, in the same clause ("No flash, so
    it is safe" is not negated; "not a statement that it is safe" is)."""
    clause = _CLAUSE_BREAK.split(text[max(0, start - 120) : start])[-1]
    return _NEGATION.search(" ".join(clause.split()[-NEGATION_WORDS:])) is not None


def _attributed(text: str, start: int, end: int) -> bool:
    """The number at text[start:end] is said to be the user's, in the same clause."""
    before = _CLAUSE_BREAK.split(text[max(0, start - 120) : start])[-1]
    after = _CLAUSE_BREAK.split(text[end : end + 160])[0]
    if _JUDGEMENT.search(before) or _JUDGEMENT.search(after):
        return False
    return bool(_ATTRIBUTED_BEFORE.search(" " + before) or _ATTRIBUTED_AFTER.match(after))


def _unnegated_match(pattern: re.Pattern, text: str) -> bool:
    return any(not _negated(text, m.start()) for m in pattern.finditer(text))


def _norm(text: str) -> str:
    return " ".join(_canon(text).lower().split())


def level_catalogue(rules: RuleSet) -> dict[str, list[tuple[str, str]]]:
    """Every (level id, label) in the rules, per hazard."""
    heat = [(lv.id, lv.label) for ls in rules.hazards.heat.level_sets for lv in ls.levels]
    distance = getattr(rules.hazards.lightning, "distance_levels", [])
    lightning = [(lv.id, lv.label) for lv in distance]
    return {"heat": heat, "lightning": lightning}


def check_answer(
    raw: str, context: AnswerContext, rules: RuleSet, question: str = ""
) -> GuardResult:
    """``question`` is the user's question: only its numbers can be quoted back, attributed."""
    parsed = _parse(raw)
    if parsed is None:
        return _reject("NOT_JSON")
    if parsed == "OFF_TOPIC":
        return GuardResult(True, "OFF_TOPIC")
    answer, sources = parsed
    answer = _canon(_plain(answer))
    if not answer:
        return _reject("EMPTY")
    if len(answer) > MAX_ANSWER_CHARS:
        return _reject("TOO_LONG")

    cited = set(_LABEL.findall(answer)) | {s for s in sources if s}
    if not cited:
        return _reject("NO_CITATION")
    if not cited <= context.labels:
        return _reject("UNKNOWN_CITATION")

    if context.general:
        return _check_general(answer, cited, context, rules, question)

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
    if not _numbers_ok(answer, grounded, question):
        return _reject("UNGROUNDED_NUMBER")
    return GuardResult(True, "OK", answer, cited)


def _numbers_ok(answer: str, grounded: set[float], question: str) -> bool:
    asked = {_to_float(t) for t in _ANY_NUMBER.findall(_canon(question))}
    for match in _NUMBER_WITH_UNIT.finditer(answer):
        value = _to_float(match.group(1))
        if _allowed(value, grounded):
            continue
        if value in asked and _attributed(answer, match.start(), match.end()):
            continue  # the user's own number, quoted back as theirs (P-21)
        return False
    return True


# --- no match: "rules yes, today no" (docs/decisions/frontend-f4-chat.md item 4) -----------

# Wording about current or coming conditions. Without a match Pitchy knows nothing about them.
_CURRENT_CONDITIONS = re.compile(
    r"\b(?:today|today's|tonight|tomorrow|now|right\s+now|currently|at\s+the\s+moment"
    r"|at\s+present|this\s+(?:match|game|afternoon|evening|morning|week|weekend)"
    r"|your\s+(?:match|game)|the\s+forecast|current\s+(?:conditions?|weather|forecast"
    r"|temperature|wbgt|heat|risk)|ngayon|mamaya|bukas)\b",
    re.I,
)
# Sentence ends; a dot between digits ("32.5 °C") is not one.
_SENTENCE_END = re.compile(r"(?<!\d)[.!?]+(?!\d)|\n")
_DOC_LABEL = re.compile(r"\[D\d{1,2}\]")


def _check_general(
    answer: str, cited: set[str], context: AnswerContext, rules: RuleSet, question: str
) -> GuardResult:
    """General guidance without a match. Level wording is allowed only in a sentence that cites
    an approved document; numbers only from the cited documents; nothing about current
    conditions; never "it is safe"."""
    documents = {d.label: d.content for d in context.documents}
    cited_docs = {c for c in cited if c in documents}
    if not cited_docs:
        return _reject("NO_DOCUMENT_CITATION")

    catalogue = level_catalogue(rules)
    ids = [level_id for levels in catalogue.values() for level_id, _ in levels]
    labels = [_norm(label) for levels in catalogue.values() for _, label in levels]
    if any(level_id in answer.lower() for level_id in ids):
        return _reject("LEVEL_NOT_GIVEN")  # raw rule ids are never the way to say it
    for sentence in _SENTENCE_END.split(answer):
        names_level = any(label in _norm(sentence) for label in labels) or any(
            p.search(sentence) for _, _, p in _LEVEL_CLAIMS
        )
        if names_level and not _DOC_LABEL.search(sentence):
            return _reject("LEVEL_NOT_FROM_DOCUMENT")

    if _unnegated_match(_CURRENT_CONDITIONS, answer):
        return _reject("CURRENT_CONDITIONS")
    if any(_unnegated_match(p, answer) for p in _SAFE_CLAIMS):
        return _reject("SAFETY_CLAIM")

    grounded = {_to_float(t) for c in cited_docs for t in _ANY_NUMBER.findall(documents[c])}
    if not _numbers_ok(answer, grounded, question):
        return _reject("UNGROUNDED_NUMBER")
    return GuardResult(True, "OK", answer, cited)
