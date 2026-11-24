"""DEC-05 validation: the Python port against the original Liljegren C program (193 cases).

fixtures/liljegren_reference.csv holds the inputs and the original program's outputs (see its
header for how it was produced). Tolerance ±0.2 °C (DEC-05); the port is far closer in practice.
"""

import csv
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest

from services.safety_engine.wbgt.liljegren import calc_wbgt

FIXTURE = Path(__file__).parent / "fixtures" / "liljegren_reference.csv"
TOLERANCE = 0.2


def _cases():
    with FIXTURE.open(encoding="utf-8") as f:
        rows = list(csv.DictReader(line for line in f if not line.startswith("#")))
    assert len(rows) == 193
    return rows


@pytest.mark.parametrize("case", _cases(), ids=lambda c: f"{c['lat']}-{c['month']}-{c['hour']}h")
def test_port_matches_the_original_program(case) -> None:
    local = datetime(int(case["year"]), int(case["month"]), int(case["day"]), int(case["hour"]),
                     int(case["minute"]), tzinfo=UTC)  # fmt: skip
    r = calc_wbgt(
        local - timedelta(hours=int(case["gmt_offset_h"])),
        int(case["averaging_min"]),
        float(case["lat"]), float(case["lon"]), float(case["solar_w_m2"]),
        float(case["pressure_hpa"]), float(case["air_temp_c"]), float(case["rh_percent"]),
        float(case["wind_m_s"]), float(case["wind_height_m"]), float(case["dT_c"]),
        bool(int(case["urban"])),
    )  # fmt: skip
    assert r.ok is (case["status"] == "0")
    assert r.wbgt == pytest.approx(float(case["wbgt_c"]), abs=TOLERANCE)
    assert r.globe == pytest.approx(float(case["globe_c"]), abs=TOLERANCE)
    assert r.natural_wet_bulb == pytest.approx(float(case["natural_wet_bulb_c"]), abs=TOLERANCE)
    assert r.wind_2m == pytest.approx(float(case["wind_2m_m_s"]), abs=0.01)
    assert abs(r.wbgt - float(case["wbgt_c"])) < 0.01  # observed agreement: within 0.0001 °C
