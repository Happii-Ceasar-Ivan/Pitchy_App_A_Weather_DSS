"""Liljegren WBGT port (DEC-05). No database, no network.

Reference value: the original wbgt.c v1.1 output for lwbgt's published Singapore fixture
(github.com/zyf0717/lwbgt, tests/python/_fixtures.py and test_api.py: float bits 59020242 =
32.502293 °C). The full 193-case check is in test_liljegren_reference.py.
"""

import math
from datetime import UTC, datetime

import pytest

from services.safety_engine.wbgt.liljegren import (
    calc_wbgt,
    solar_position,
    stability_class,
    wbgt_screening,
    wind_at_2m,
)

SINGAPORE = dict(  # 2024-04-15 14:30 local (UTC+8) = 06:30 UTC
    at=datetime(2024, 4, 15, 6, 30, tzinfo=UTC), averaging_minutes=60, latitude=1.3521,
    longitude=103.8198, solar=742.0, pressure=1008.4, air_temperature=32.1,
    relative_humidity=68.0, wind_speed=2.8, wind_height=10.0,
)  # fmt: skip
TOLERANCE = 0.2  # °C, DEC-05 validation tolerance


def test_matches_the_original_c_program_for_the_singapore_reference() -> None:
    r = calc_wbgt(**SINGAPORE, vertical_temperature_difference=-0.4, urban=True)
    assert r.ok
    assert r.wbgt == pytest.approx(32.502293, abs=TOLERANCE)
    assert r.wbgt == pytest.approx(32.502293, abs=0.01)  # in practice much closer
    assert r.wbgt == pytest.approx(0.1 * 32.1 + 0.2 * r.globe + 0.7 * r.natural_wet_bulb)


def test_night_has_no_sun_and_wbgt_below_air_temperature() -> None:
    r = calc_wbgt(at=datetime(2024, 4, 14, 18, 30, tzinfo=UTC), averaging_minutes=60,
                  latitude=1.3521, longitude=103.8198, solar=0.0, pressure=1009.7,
                  air_temperature=27.0, relative_humidity=88.0, wind_speed=1.1, wind_height=10.0,
                  vertical_temperature_difference=0.2, urban=True)  # fmt: skip
    assert r.ok and r.cos_zenith < 0 and r.direct_fraction == 0.0
    assert r.natural_wet_bulb < r.wbgt < 27.0


def test_more_sun_means_higher_wbgt() -> None:
    low = calc_wbgt(**{**SINGAPORE, "solar": 200.0}, vertical_temperature_difference=-1, urban=True)
    high = calc_wbgt(**SINGAPORE, vertical_temperature_difference=-1, urban=True)
    assert high.wbgt > low.wbgt


def test_out_of_range_date_fails_instead_of_guessing() -> None:
    r = calc_wbgt(**{**SINGAPORE, "at": datetime(2051, 1, 1, tzinfo=UTC)},
                  vertical_temperature_difference=-1, urban=True)  # fmt: skip
    assert not r.ok and r.wbgt is None


def test_sun_is_high_at_local_noon_near_the_equator_at_equinox() -> None:
    altitude, distance = solar_position(2024, 3, 20 + 12 / 24, 0.0, 0.0)
    assert altitude > 85 and 0.98 < distance < 1.02
    night, _ = solar_position(2024, 3, 20.0, 0.0, 0.0)  # midnight UT at lon 0
    assert night < -60


def test_wind_profile_follows_the_epa_table() -> None:
    assert stability_class(True, 1.0, 950.0, 0.0) == 1  # strong sun, light wind: unstable
    assert stability_class(False, 1.0, 0.0, 1.0) == 6  # night inversion, light wind
    assert stability_class(False, 1.0, 0.0, -1.0) == 5
    assert wind_at_2m(5.0, 10.0, 1, urban=True) == pytest.approx(5.0 * 0.2**0.15)
    assert wind_at_2m(0.01, 10.0, 1, urban=False) == 0.13  # minimum speed


def test_screening_keeps_the_highest_of_the_unknown_site_inputs() -> None:
    s = wbgt_screening(**{**SINGAPORE, "at": datetime(2024, 4, 14, 18, 30, tzinfo=UTC),
                          "solar": 0.0, "wind_speed": 1.0})  # fmt: skip
    runs = [calc_wbgt(**{**SINGAPORE, "at": datetime(2024, 4, 14, 18, 30, tzinfo=UTC),
                         "solar": 0.0, "wind_speed": 1.0},
                      urban=u, vertical_temperature_difference=d).wbgt
            for u in (False, True) for d in (-1.0, 1.0)]  # fmt: skip
    assert s.result.wbgt == max(runs)
    assert s.spread == pytest.approx(max(runs) - min(runs))
    assert all(math.isfinite(x) for x in runs)
