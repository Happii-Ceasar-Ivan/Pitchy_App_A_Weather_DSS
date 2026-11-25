"""English number words to digits, so the answer check also sees "thirty minutes" (B6).

Only the copy the check reads is changed; the user still sees the answer as written. The
documents and the question go through the same conversion, so both sides are compared alike.

- Cardinals and ordinals up to 999: "five", "thirty-five", "seventy-fifth", "one hundred and
  twenty". Each run of number words becomes one number; "thirtieth and seventy-fifth" stays two
  numbers ("and" joins only after "hundred").
- "second" is never read as an ordinal ("thirty-second" is the 30-second rule, not the 32nd),
  and "a"/"an" are never read as 1.
- Not handled: decimals in words ("thirty-two point five"), Filipino number words. Answers are in
  English and the prompt asks for digits; these are a backup.
"""

import re

_UNITS = {
    "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
    "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13,
    "fourteen": 14, "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18,
    "nineteen": 19,
    "first": 1, "third": 3, "fourth": 4, "fifth": 5, "sixth": 6, "seventh": 7, "eighth": 8,
    "ninth": 9, "tenth": 10, "eleventh": 11, "twelfth": 12, "thirteenth": 13,
    "fourteenth": 14, "fifteenth": 15, "sixteenth": 16, "seventeenth": 17, "eighteenth": 18,
    "nineteenth": 19,
}  # fmt: skip
_TENS = {
    "twenty": 20, "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70,
    "eighty": 80, "ninety": 90,
    "twentieth": 20, "thirtieth": 30, "fortieth": 40, "fiftieth": 50, "sixtieth": 60,
    "seventieth": 70, "eightieth": 80, "ninetieth": 90,
}  # fmt: skip
_HUNDRED = {"hundred", "hundredth"}
_WORD = "|".join(sorted([*_UNITS, *_TENS, *_HUNDRED], key=len, reverse=True))
# A run: number words joined by spaces or hyphens; "and" only right after "hundred".
_RUN = re.compile(
    rf"\b(?:{_WORD})(?:(?:[\s-]+|\s+and\s+)(?:{_WORD}))*\b(?!-?second)|\b(?:{_WORD})\b",
    re.IGNORECASE,
)
_SPLIT = re.compile(r"[\s-]+(?:and\s+)?")


def _value(words: list[str]) -> list[int]:
    """Values of a run of number words; a run that is not one number gives several."""
    values: list[int] = []
    current: int | None = None
    last = ""  # "unit", "tens", "hundred"
    for word in words:
        w = word.lower()
        if w in _HUNDRED and current is not None and last == "unit" and current < 10:
            current *= 100
            last = "hundred"
        elif w in _TENS and (current is None or (last == "hundred")):
            current = (current or 0) + _TENS[w]
            last = "tens"
        elif w in _UNITS and (
            current is None or (last == "tens" and _UNITS[w] < 10) or (last == "hundred")
        ):
            current = (current or 0) + _UNITS[w]
            last = "unit"
        else:  # not part of the same number: this word starts a new one
            if current is not None:
                values.append(current)
            if w in _UNITS:
                current, last = _UNITS[w], "unit"
            elif w in _TENS:
                current, last = _TENS[w], "tens"
            else:  # "hundred" with nothing before it
                current, last = None, ""
    if current is not None:
        values.append(current)
    return values


def numerals(text: str) -> str:
    """``text`` with English number words written as digits ("thirty-five minutes" -> "35
    minutes")."""

    def swap(match: re.Match) -> str:
        words = [w for w in _SPLIT.split(match.group(0)) if w]
        values = _value(words)
        return " and ".join(str(v) for v in values) if values else match.group(0)

    return _RUN.sub(swap, text)
