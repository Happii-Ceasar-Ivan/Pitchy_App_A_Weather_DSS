# WBGT (DEC-05): Liljegren et al. (2008)

`liljegren.py` is a Python port of **Liljegren's WBGT v1.1** (`wbgt.c`, Argonne National Laboratory, 2008), kept under its open source licence (notice and changes are at the top of the file).

> This product includes software produced by UChicago Argonne, LLC under Contract No. DE-AC02-06CH11357 with the Department of Energy.

## Inputs (Open-Meteo, per forecast stamp T)

| Input | Open-Meteo variable | Time meaning |
| --- | --- | --- |
| Air temperature | `temperature_2m` (°C) | instant at T |
| Relative humidity | `relative_humidity_2m` (%) | instant at T |
| Wind | `wind_speed_10m` (m/s), height 10 m | instant at T; converted to 2 m by Liljegren's stability-class power law |
| Pressure | `surface_pressure` (hPa) | instant at T (added 2026-11-24) |
| Solar | `shortwave_radiation` (W/m²) | mean of the hour before T (`averaging_minutes = 60`, so the sun's position is taken at T − 30 min) |

- The direct-beam share is estimated by Liljegren's own method from total solar radiation and the sun's position (Open-Meteo's direct/diffuse values are not needed).
- **Unknown site inputs:** urban vs rural wind profile, and the night-time vertical temperature difference (only its sign matters). `wbgt_screening` computes all four combinations and keeps the **highest** WBGT; the engine adds a `SCREENING_ASSUMPTION` limitation when they differ by ≥ 0.05 °C.
- Missing, non-`ok`, or wrong-unit inputs make WBGT unavailable. Nothing is interpolated or filled in.

## How the engine uses it (`../engine.py`)

- **When:** FIFA's measurement times, 90 and 60 minutes before kickoff. Each uses the forecast stamped at the first whole hour at or after that time (instant values at that hour; radiation averaged over the hour before, which contains the time). The higher value sets the level. Hourly WBGT through the match is shown for information.
- **Level:** from `thresholds/rules.yaml` for the match's age group (senior 32 °C; youth_u20 28 °C), only when the forecast is **current** (DEC-04). Stale forecasts are shown with `STALE_INPUT` and no level.
- Always labelled as a forecast estimate (`FORECAST_ESTIMATE`). It never replaces the on-site measurement.

## Validation (complete, 2026-11-24)

- Reference: the **original C program** (`wbgt.c.original`, v1.1, unmodified, as kept in github.com/mdljts/wbgt and github.com/zyf0717/lwbgt `upstream/`). Tolerance ±0.2 °C (DEC-05).
- **193 cases** (`tests/safety_engine/fixtures/liljegren_reference.csv`):
  - Manila and Capas coordinates; March, May and November; local hours 06:00 to 22:00 (day and night).
  - Solar 0–850 W/m², 26–34.5 °C, 55–90 % humidity, wind 0.8–6.5 m/s at 10 m; urban/rural; both night stability signs.
  - Plus lwbgt's published Singapore case (32.5023 °C).
  - The original's WBGT ranges from 25.4 to 34.5 °C, across both the 28 °C and 32 °C levels.
- **How the reference was made:** the project team compiled the original with `zig cc` 0.17.1 (`-std=c89 -O2 -fno-fast-math -ffp-contract=off`) and a small harness (`backend/.tmp/wbgt_ref/`, local only), then ran it on 2026-11-24.
- **Result:** the port matches every case within **0.0001 °C** for WBGT, globe and natural wet-bulb temperature, with the same success or failure on every case. `tests/safety_engine/test_liljegren_reference.py` keeps checking it.
