"""Deterministic topic check before any AI call (off-topic layer 1).

A question that mentions nothing about weather, football, the match or safety gets Pitchy's fixed
decline without calling a provider, so it costs no AI quota and the model never gets a chance to
answer it. Words are matched as stems inside the lowercased question, in English and common
Filipino/Taglish words, so "maglaro" matches "laro" and "lightning's" matches "lightning".

This layer is deliberately generous (a false "on topic" only reaches layers 2 and 3: the model's
off-topic flag and the answer check's citation rule). It must never be the only defence.
"""

import re

OFF_TOPIC_MESSAGE = (
    "I can only help with this match's weather safety: heat, lightning, rain and official "
    "alerts. Please ask about those."
)

_STEMS = (
    # weather and hazards
    "weather", "forecast", "heat", "hot", "temperat", "wbgt", "humid", "sun", "uv", "rain",
    "storm", "thunder", "lightning", "flash", "typhoon", "cyclone", "signal", "wind", "flood",
    "cloud", "degree", "celsius", "pagasa", "alert", "advisory", "warning", "climate",
    # football and the match
    "match", "game", "play", "kickoff", "kick-off", "kick off", "football", "soccer", "futsal",
    "pitch", "field", "stadium", "venue", "training", "practice", "tournament", "fixture",
    "referee", "official", "coach", "player", "team", "spectator", "fan", "crowd",
    "halftime", "half-time", "minute",
    # safety, health and decisions
    "safe", "danger", "risk", "cooling", "break", "water", "drink", "hydrat", "shelter",
    "shade", "cramp", "faint", "dizzy", "heatstroke", "heat stroke", "exhaust", "medical",
    "ambulance", "aed", "first aid", "postpone", "cancel", "suspend", "delay", "stop",
    "restart", "resume", "evacuat", "rule", "fifa", "afc", "pff", "protocol", "guideline",
    "level", "today", "tonight", "tomorrow", "later",  # not "now": it is inside "know"
    # Filipino / Taglish
    "init", "mainit", "ulan", "umuulan", "kidlat", "kulog", "bagyo", "hangin", "panahon",
    "laro", "laban", "maglaro", "tubig", "pahinga", "ligtas", "delikado", "mamaya", "ngayon",
    "bukas", "kanselado", "ipagpaliban",
)  # fmt: skip
_WORDS = re.compile("|".join(re.escape(s) for s in sorted(_STEMS, key=len, reverse=True)))


def is_on_topic(question: str) -> bool:
    return _WORDS.search(question.lower()) is not None
