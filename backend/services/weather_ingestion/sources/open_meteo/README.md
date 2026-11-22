# Open-Meteo adapter

Source id: `open_meteo`. Decision: DEC-01 (2026-11-22). Licence: CC BY 4.0. The app must show "Weather data by Open-Meteo.com" with a link wherever this data appears.

## Request

`GET https://api.open-meteo.com/v1/forecast`. One call per venue, no API key (Non-Commercial licence).

| Param | Value |
| --- | --- |
| `latitude`, `longitude` | the venue's coordinates (`locations` row) |
| `hourly` | the 15 variables in `adapter.py: HOURLY_UNITS` |
| `wind_speed_unit` | `ms` |
| `timezone` | `GMT` (times are UTC) |

## Normalization

- Parameter codes are Open-Meteo's own names (e.g. `temperature_2m`).
- Each hourly value is valid for its hour: `valid_from` = the time given, `valid_until` = +1 h, in UTC.
- Units are checked against `HOURLY_UNITS`. A different unit means `SOURCE_RESPONSE_CHANGED`; nothing is converted silently.
- `null` → `value_state = 'missing'`, never guessed.
- `retrieved_at` is set by the database when stored. Open-Meteo doesn't report which model run it used, so `source_issued_at` is empty.
- The data comes from the nearest grid point, roughly 3 km away. Its coordinates and elevation are kept in the raw payload.

## Failure cases

| Code | When |
| --- | --- |
| `TIMEOUT`, `NETWORK_ERROR`, `HTTP_<n>` | Open-Meteo is unreachable or refuses the request. |
| `SOURCE_RESPONSE_CHANGED` | Not JSON, non-UTC offset, a missing variable, a changed unit, or unparseable times. |

Tests and the captured sample: `backend/tests/sources/open_meteo/`.
