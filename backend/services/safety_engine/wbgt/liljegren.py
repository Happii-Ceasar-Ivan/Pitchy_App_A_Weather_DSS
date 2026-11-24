"""Outdoor WBGT by Liljegren et al. (2008): a Python port of Liljegren's WBGT v1.1 (wbgt.c).

DEC-05. Pure functions, no I/O. See README.md in this folder for the method, inputs and validation.

Ported from ``wbgt.c`` (WBGT, Version 1.1, James C. Liljegren, Decision & Information Sciences
Division, Argonne National Laboratory; solar position by Nels Larson, Pacific Northwest National
Laboratory), redistributed under its open source licence:

    Copyright © 2008, UChicago Argonne, LLC. All Rights Reserved.

    Redistribution and use in source and binary forms, with or without modification, are
    permitted provided that the following conditions are met:
    1. Redistributions of source code must retain the above copyright notice, this list of
       conditions and the following disclaimer. Software changes, modifications, or derivative
       works, should be noted with comments and the author and organization's name.
    2. Redistributions in binary form must reproduce the above copyright notice, this list of
       conditions and the following disclaimer in the documentation and/or other materials
       provided with the distribution.
    3. Neither the names of UChicago Argonne, LLC or the Department of Energy nor the names of
       its contributors may be used to endorse or promote products derived from this software
       without specific prior written permission.
    4. The software and the end-user documentation included with the redistribution, if any,
       must include the following acknowledgment: "This product includes software produced by
       UChicago Argonne, LLC under Contract No. DE-AC02-06CH11357 with the Department of
       Energy."

    DISCLAIMER: THE SOFTWARE IS SUPPLIED "AS IS" WITHOUT WARRANTY OF ANY KIND. NEITHER THE
    UNITED STATES GOVERNMENT, NOR THE UNITED STATES DEPARTMENT OF ENERGY, NOR UCHICAGO ARGONNE,
    LLC, NOR ANY OF THEIR EMPLOYEES, MAKES ANY WARRANTY, EXPRESS OR IMPLIED, OR ASSUMES ANY LEGAL
    LIABILITY OR RESPONSIBILITY FOR THE ACCURACY, COMPLETENESS, OR USEFULNESS OF ANY INFORMATION,
    DATA, APPARATUS, PRODUCT, OR PROCESS DISCLOSED, OR REPRESENTS THAT ITS USE WOULD NOT INFRINGE
    PRIVATELY OWNED RIGHTS.

This product includes software produced by UChicago Argonne, LLC under Contract No.
DE-AC02-06CH11357 with the Department of Energy.

Changes from the original (Pitchy project, PUPQC thesis team, 2026-11-24):
- Translated from C to Python. Arithmetic is double precision (the original uses single
  precision floats), so results can differ from the C program by a few hundredths of a degree.
- The demonstration ``main`` and its file input are omitted; times are taken from a UTC datetime
  (GMT offset 0) instead of local standard time.
- A solar-position failure (out-of-range date or coordinates) is returned as a failed result
  instead of reading unset values.
- ``wbgt_screening`` (not in the original) evaluates the inputs the forecast cannot supply
  (urban/rural and the night-time vertical temperature difference) both ways and keeps the
  highest WBGT.
Equations, constants, convergence rules and the stability table are unchanged.
"""

import math
from dataclasses import dataclass
from datetime import UTC, datetime

# --- constants (wbgt.c) ------------------------------------------------------------------------
PI = 3.1415926535897932
TWOPI = 6.2831853071795864
DEG_RAD = 0.017453292519943295
RAD_DEG = 57.295779513082323

SOLAR_CONST = 1367.0
STEFANB = 5.6696e-8
CP = 1003.5
M_AIR = 28.97
M_H2O = 18.015
RATIO = CP * M_AIR / M_H2O
R_GAS = 8314.34
R_AIR = R_GAS / M_AIR
PR = CP / (CP + 1.25 * R_AIR)

EMIS_WICK, ALB_WICK, D_WICK, L_WICK = 0.95, 0.4, 0.007, 0.0254
EMIS_GLOBE, ALB_GLOBE, D_GLOBE = 0.95, 0.05, 0.0508
EMIS_SFC, ALB_SFC = 0.999, 0.45

CZA_MIN = 0.00873
NORMSOLAR_MAX = 0.85
REF_HEIGHT = 2.0
MIN_SPEED = 0.13
CONVERGENCE = 0.02
MAX_ITER = 50
FAILED = -9999.0


@dataclass(frozen=True)
class WbgtResult:
    ok: bool  # False: the globe or wet-bulb solution did not converge, or bad date/coordinates
    wbgt: float | None  # °C
    globe: float | None  # globe temperature, °C
    natural_wet_bulb: float | None  # °C
    psychrometric_wet_bulb: float | None  # °C
    wind_2m: float  # wind speed used at 2 m, m/s
    cos_zenith: float | None
    direct_fraction: float | None
    solar_used: float | None  # irradiance after the original's consistency limit, W/m²


# --- solar position (Nels Larson, A. A. 1990 low-precision formulas) ---------------------------


def _daynum(year: int, month: int, day: int) -> int:
    begmonth = (0, 0, 31, 59, 90, 120, 151, 181, 212, 243, 273, 304, 334)
    leap = (year % 4 == 0 and year % 100 != 0) or year % 400 == 0
    dnum = begmonth[month] + day
    if leap and month > 2:
        dnum += 1
    return dnum


def solar_position(year: int, month: int, day: float, latitude: float, longitude: float):
    """Apparent solar altitude (deg, refraction added) and Earth-Sun distance (AU), or None.

    ``day`` is the day.fraction of the month in UT (month > 0) or of the year (month == 0)."""
    if not (-90.0 <= latitude <= 90.0 and -180.0 <= longitude <= 180.0):
        return None
    if year < 1950 or year > 2049:
        return None
    if month != 0:
        if month < 1 or month > 12 or day < 0.0 or day > 33.0:
            return None
        daynumber = _daynum(year, month, int(day))
    else:
        if day < 0.0 or day > 368.0:
            return None
        daynumber = int(day)

    delta_years = year - 2000
    delta_days = delta_years * 365 + int(delta_years / 4) + daynumber  # C integer division
    if year > 2000:
        delta_days += 1
    days_j2000 = delta_days - 1.5
    cent_j2000 = days_j2000 / 36525.0
    ut = math.modf(day)[0]
    days_j2000 += ut
    ut *= 24.0

    mean_anomaly = math.modf((357.528 + 0.9856003 * days_j2000) / 360.0)[0] * TWOPI
    mean_longitude = math.modf((280.460 + 0.9856474 * days_j2000) / 360.0)[0] * TWOPI
    mean_obliquity = (23.439 - 4.0e-7 * days_j2000) * DEG_RAD
    ecliptic_long = (
        1.915 * math.sin(mean_anomaly) + 0.020 * math.sin(2.0 * mean_anomaly)
    ) * DEG_RAD + mean_longitude
    distance = 1.00014 - 0.01671 * math.cos(mean_anomaly) - 0.00014 * math.cos(2.0 * mean_anomaly)

    ap_ra = math.atan2(math.cos(mean_obliquity) * math.sin(ecliptic_long), math.cos(ecliptic_long))
    if ap_ra < 0.0:
        ap_ra += TWOPI
    ap_ra = math.modf(ap_ra / TWOPI)[0] * 24.0
    ap_dec = math.asin(math.sin(mean_obliquity) * math.sin(ecliptic_long))

    gmst0h = 24110.54841 + cent_j2000 * (
        8640184.812866 + cent_j2000 * (0.093104 - cent_j2000 * 6.2e-6)
    )
    gmst0h = math.modf(gmst0h / 3600.0 / 24.0)[0] * 24.0
    if gmst0h < 0.0:
        gmst0h += 24.0
    lmst = gmst0h + ut * 1.00273790934 + longitude / 15.0
    lmst = math.modf(lmst / 24.0)[0] * 24.0
    if lmst < 0.0:
        lmst += 24.0

    local_ha = lmst - ap_ra
    if local_ha < -12.0:
        local_ha += 24.0
    elif local_ha > 12.0:
        local_ha -= 24.0
    lat = latitude * DEG_RAD
    local_ha = local_ha / 24.0 * TWOPI

    altitude = math.asin(
        math.sin(ap_dec) * math.sin(lat) + math.cos(ap_dec) * math.cos(local_ha) * math.cos(lat)
    )
    tan_alt = math.tan(altitude) if abs(altitude) < 1.57079615 else 6.0e6
    altitude *= RAD_DEG

    pressure, temp = 1013.25, 15.0  # standard atmosphere used for refraction
    if altitude < -1.0 or tan_alt == 6.0e6:
        refraction = 0.0
    elif altitude < 19.225:
        refraction = (0.1594 + altitude * (0.0196 + 0.00002 * altitude)) * pressure
        refraction /= (1.0 + altitude * (0.505 + 0.0845 * altitude)) * (273.0 + temp)
    else:
        refraction = 0.00452 * (pressure / (273.0 + temp)) / tan_alt
    return altitude + refraction, distance


def solar_parameters(year, month, day, latitude, longitude, solar):
    """(solar, cos_zenith, direct_fraction) as in calc_solar_parameters, or None."""
    position = solar_position(year, month, day, latitude, longitude)
    if position is None:
        return None
    elevation, soldist = position
    cza = math.cos((90.0 - elevation) * DEG_RAD)
    toasolar = SOLAR_CONST * max(0.0, cza) / (soldist * soldist)
    if cza < CZA_MIN:
        toasolar = 0.0
    if toasolar > 0.0:
        normsolar = min(solar / toasolar, NORMSOLAR_MAX)
        solar = normsolar * toasolar
        if normsolar > 0.0:
            fdir = math.exp(3.0 - 1.34 * normsolar - 1.65 / normsolar)
            fdir = max(min(fdir, 0.9), 0.0)
        else:
            fdir = 0.0
    else:
        fdir = 0.0
    return solar, cza, fdir


# --- thermophysical properties -----------------------------------------------------------------


def esat(tk: float, phase: int = 0) -> float:
    """Saturation vapour pressure (mb) over water (0) or ice (1); Buck (1981)."""
    if phase == 0:
        es = 6.1121 * math.exp(17.502 * (tk - 273.15) / (tk - 32.18))
    else:
        es = 6.1115 * math.exp(22.452 * (tk - 273.15) / (tk - 0.6))
    return 1.004 * es  # moist-air correction, pressure > 800 mb


def dew_point(e: float, phase: int = 0) -> float:
    if phase == 0:
        z = math.log(e / (6.1121 * 1.004))
        return 273.15 + 240.97 * z / (17.502 - z)
    z = math.log(e / (6.1115 * 1.004))
    return 273.15 + 272.55 * z / (22.452 - z)


def viscosity(tk: float) -> float:
    sigma, eps_kappa = 3.617, 97.0
    omega = (tk / eps_kappa - 2.9) / 0.4 * (-0.034) + 1.048
    return 2.6693e-6 * math.sqrt(M_AIR * tk) / (sigma * sigma * omega)


def thermal_cond(tk: float) -> float:
    return (CP + 1.25 * R_AIR) * viscosity(tk)


def diffusivity(tk: float, pair: float) -> float:
    pcrit_air, pcrit_h2o, tcrit_air, tcrit_h2o = 36.4, 218.0, 132.0, 647.3
    a, b = 3.640e-4, 2.334
    pcrit13 = (pcrit_air * pcrit_h2o) ** (1.0 / 3.0)
    tcrit512 = (tcrit_air * tcrit_h2o) ** (5.0 / 12.0)
    tcrit12 = math.sqrt(tcrit_air * tcrit_h2o)
    mmix = math.sqrt(1.0 / M_AIR + 1.0 / M_H2O)
    patm = pair / 1013.25
    return a * (tk / tcrit12) ** b * pcrit13 * tcrit512 * mmix / patm * 1e-4


def evap(tk: float) -> float:
    return (313.15 - tk) / 30.0 * (-71100.0) + 2.4073e6


def emis_atm(tk: float, rh: float) -> float:
    return 0.575 * (rh * esat(tk)) ** 0.143


def h_sphere_in_air(diameter: float, tk: float, pair: float, speed: float) -> float:
    density = pair * 100.0 / (R_AIR * tk)
    re = max(speed, MIN_SPEED) * density * diameter / viscosity(tk)
    nu = 2.0 + 0.6 * math.sqrt(re) * PR**0.3333
    return nu * thermal_cond(tk) / diameter


def h_cylinder_in_air(diameter, length, tk, pair, speed) -> float:
    a, b, c = 0.56, 0.281, 0.4
    density = pair * 100.0 / (R_AIR * tk)
    re = max(speed, MIN_SPEED) * density * diameter / viscosity(tk)
    nu = b * re ** (1.0 - c) * PR ** (1.0 - a)
    return nu * thermal_cond(tk) / diameter


# --- globe and wet-bulb temperatures -----------------------------------------------------------


def globe_temperature(tk, rh, pair, speed, solar, fdir, cza) -> float:
    tsfc = tk
    prev = tk
    for _ in range(MAX_ITER):
        tref = 0.5 * (prev + tk)
        h = h_sphere_in_air(D_GLOBE, tref, pair, speed)
        new = (
            0.5 * (emis_atm(tk, rh) * tk**4 + EMIS_SFC * tsfc**4)
            - h / (STEFANB * EMIS_GLOBE) * (prev - tk)
            + solar / (2.0 * STEFANB * EMIS_GLOBE) * (1.0 - ALB_GLOBE)
            * (fdir * (1.0 / (2.0 * cza) - 1.0) + 1.0 + ALB_SFC)
        ) ** 0.25  # fmt: skip
        if abs(new - prev) < CONVERGENCE:
            return new - 273.15
        prev = 0.9 * prev + 0.1 * new
    return FAILED


def wet_bulb(tk, rh, pair, speed, solar, fdir, cza, radiative: bool) -> float:
    """Natural (radiative=True) or psychrometric (False) wet-bulb temperature, °C."""
    a = 0.56
    tsfc = tk
    sza = math.acos(cza)
    eair = rh * esat(tk)
    prev = dew_point(eair)
    for _ in range(MAX_ITER):
        tref = 0.5 * (prev + tk)
        h = h_cylinder_in_air(D_WICK, L_WICK, tref, pair, speed)
        fatm = STEFANB * EMIS_WICK * (
            0.5 * (emis_atm(tk, rh) * tk**4 + EMIS_SFC * tsfc**4) - prev**4
        ) + (1.0 - ALB_WICK) * solar * (
            (1.0 - fdir) * (1.0 + 0.25 * D_WICK / L_WICK)
            + fdir * ((math.tan(sza) / PI) + 0.25 * D_WICK / L_WICK)
            + ALB_SFC
        )
        ewick = esat(prev)
        density = pair * 100.0 / (R_AIR * tref)
        sc = viscosity(tref) / (density * diffusivity(tref, pair))
        new = (
            tk
            - evap(tref) / RATIO * (ewick - eair) / (pair - ewick) * (PR / sc) ** a
            + (fatm / h * (1 if radiative else 0))
        )
        if abs(new - prev) < CONVERGENCE:
            return new - 273.15
        prev = 0.9 * prev + 0.1 * new
    return FAILED


# --- wind at 2 m (EPA-454/5-99-005, section 6.2.5) ---------------------------------------------

_LSRDT = (
    (1, 1, 2, 4, 0, 5, 6, 0),
    (1, 2, 3, 4, 0, 5, 6, 0),
    (2, 2, 3, 4, 0, 4, 4, 0),
    (3, 3, 4, 4, 0, 0, 0, 0),
    (3, 4, 4, 4, 0, 0, 0, 0),
    (0, 0, 0, 0, 0, 0, 0, 0),
)


def stability_class(daytime: bool, speed: float, solar: float, dt: float) -> int:
    if daytime:
        j = 0 if solar >= 925.0 else 1 if solar >= 675.0 else 2 if solar >= 175.0 else 3
        i = 4 if speed >= 6.0 else 3 if speed >= 5.0 else 2 if speed >= 3.0 else (
            1 if speed >= 2.0 else 0
        )  # fmt: skip
    else:
        j = 6 if dt >= 0.0 else 5
        i = 2 if speed >= 2.5 else 1 if speed >= 2.0 else 0
    return _LSRDT[i][j]


def wind_at_2m(speed: float, zspeed: float, stab: int, urban: bool) -> float:
    urban_exp = (0.15, 0.15, 0.20, 0.25, 0.30, 0.30)
    rural_exp = (0.07, 0.07, 0.10, 0.15, 0.35, 0.55)
    exponent = (urban_exp if urban else rural_exp)[stab - 1]
    return max(speed * (REF_HEIGHT / zspeed) ** exponent, MIN_SPEED)


# --- WBGT --------------------------------------------------------------------------------------


def calc_wbgt(
    at: datetime,
    averaging_minutes: int,
    latitude: float,
    longitude: float,
    solar: float,
    pressure: float,
    air_temperature: float,
    relative_humidity: float,
    wind_speed: float,
    wind_height: float,
    vertical_temperature_difference: float,
    urban: bool,
) -> WbgtResult:
    """Outdoor WBGT (°C) for inputs stamped at ``at`` (UTC) and averaged over the
    ``averaging_minutes`` before it. Units: W/m², hPa, °C, %, m/s, m, °C."""
    at = at.astimezone(UTC)
    solar = max(solar, 0.0)
    wind_speed = max(wind_speed, 0.0)
    hour_gmt = at.hour + (at.minute - 0.5 * averaging_minutes) / 60.0
    dday = at.day + hour_gmt / 24.0
    params = solar_parameters(at.year, at.month, dday, latitude, longitude, solar)
    if params is None:
        return WbgtResult(False, None, None, None, None, wind_speed, None, None, None)
    solar, cza, fdir = params

    speed = wind_speed
    if wind_height != REF_HEIGHT:
        stab = stability_class(cza > 0.0, speed, solar, vertical_temperature_difference)
        speed = wind_at_2m(speed, wind_height, stab, urban)

    tk = air_temperature + 273.15
    rh = 0.01 * relative_humidity
    tg = globe_temperature(tk, rh, pressure, speed, solar, fdir, cza)
    tnwb = wet_bulb(tk, rh, pressure, speed, solar, fdir, cza, True)
    tpsy = wet_bulb(tk, rh, pressure, speed, solar, fdir, cza, False)
    if tg == FAILED or tnwb == FAILED:
        return WbgtResult(False, None, None, None, None, speed, cza, fdir, solar)
    wbgt = 0.1 * air_temperature + 0.2 * tg + 0.7 * tnwb
    return WbgtResult(True, wbgt, tg, tnwb, tpsy if tpsy != FAILED else None, speed, cza, fdir,
                      solar)  # fmt: skip


@dataclass(frozen=True)
class ScreeningResult:
    result: WbgtResult  # the highest-WBGT evaluation
    urban: bool
    vertical_temperature_difference: float
    spread: float  # max - min WBGT across the evaluations, °C (0 when the choices don't matter)


def wbgt_screening(**inputs) -> ScreeningResult | None:
    """Evaluate the inputs a forecast cannot supply both ways and keep the highest WBGT.

    Urban/rural (wind-profile exponent) and the vertical temperature difference (night-time
    stability: only its sign matters) are unknown for a forecast point, so all four combinations
    are computed. Returns None if no combination converges."""
    runs = []
    for urban in (False, True):
        for dt in (-1.0, 1.0):
            r = calc_wbgt(urban=urban, vertical_temperature_difference=dt, **inputs)
            if r.ok:
                runs.append((r.wbgt, urban, dt, r))
    if not runs:
        return None
    best = max(runs, key=lambda x: x[0])
    return ScreeningResult(best[3], best[1], best[2], best[0] - min(x[0] for x in runs))
