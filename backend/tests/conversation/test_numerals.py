"""Number words to digits for the answer check (services/conversation/numerals.py)."""

import pytest

from services.conversation.numerals import numerals


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("thirty minutes", "30 minutes"),
        ("Ten packets", "10 packets"),
        ("thirty-five degrees", "35 degrees"),
        ("twenty five", "25"),
        ("one hundred and twenty minutes", "120 minutes"),
        ("two hundred", "200"),
        ("the thirtieth and seventy-fifth minutes", "the 30 and 75 minutes"),
        ("ninety and sixty minutes before", "90 and 60 minutes before"),
        ("three-minute breaks", "3-minute breaks"),
        ("within ten kilometres", "within 10 kilometres"),
        ("the thirty-second rule", "the 30-second rule"),  # not the 32nd
        ("the second half", "the second half"),  # "second" is never an ordinal
        ("a break", "a break"),  # "a" is never 1
        ("five six", "5 and 6"),
        ("thirty forty", "30 and 40"),
        ("hundred minutes", "hundred minutes"),
        ("often none of this", "often none of this"),  # words that only contain number words
        ("32.5 °C stays 32.5 °C", "32.5 °C stays 32.5 °C"),
    ],
)
def test_numerals(text, expected) -> None:
    assert numerals(text) == expected
