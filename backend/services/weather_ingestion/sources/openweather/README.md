# OpenWeather adapter

Source id: `openweather`. Decision: P-30 (2026-11-28). API: One Call API 3.0, Base plan, account cap 1,000 calls/day (the free limit). Licence: ODbL. The app must show "Weather data © OpenWeather" wherever this data appears (`ATTRIBUTIONS` in `api/routes/match_contexts.py`; the visible credit is frontend work).

Role: a third forecast source shown alongside Open-Meteo and PAGASA, with its own status, times and provenance. **Display and citation only**: no safety rule reads it (P-30 Q4).

## Request

`GET https://api.openweathermap.org/data/3.0/onecall`. One call per venue.

| Param | Value |
| --- | --- |
| `lat`, `lon` | the venue's coordinates (`locations` row) |
| `units` | `metric` (the response states no units; this request parameter fixes them) |
| `exclude` | `current,minutely,daily,alerts` (only the 48 hourly steps) |
| `appid` | `OPENWEATHER_API_KEY` (`SecretStr` in `shared/settings.py`) |

The key is in the query string, so the URL is a secret: never logged (httpx URL logging is off in the allowlisted client), never stored, never in an error. The response body has no key. Without a key the adapter sends nothing and fails with `NOT_CONFIGURED`.

## Normalization

Field meanings and units come from the One Call 3.0 docs (read 2026-11-28), not guessed.

| Stored code | Field | Unit | Notes |
| --- | --- | --- | --- |
| `temp` | `temp` | °C | height not stated |
| `humidity` | `humidity` | % | |
| `dew_point` | `dew_point` | °C | |
| `pressure_msl` | `pressure` | hPa | docs: "on the sea level" (not surface pressure) |
| `clouds` | `clouds` | % | |
| `uvi` | `uvi` | UV index | |
| `wind_speed` | `wind_speed` | m/s | height not stated |
| `wind_gust` | `wind_gust` | m/s | "(where available)" |
| `wind_deg` | `wind_deg` | ° | meteorological |
| `pop` | `pop` | % | docs give 0..1; stored × 100 |
| `rain_1h` | `rain.1h` | mm/h | "(where available)" |

- Times: `dt` is "Unix, UTC". Each value is stored for `[dt, dt + 1 h)`. The parser requires every `dt` on the hour and 1 h apart.
- Not stated by OpenWeather: which part of the hour `pop` and `rain.1h` describe. They are shown per source in the consolidated view but kept out of the cross-source range (`OW_WINDOW_NOT_STATED` in `relevance/consolidation.py`) until confirmed.
- Optional fields that are absent (`wind_gust`, `rain.1h`) are stored as `value_state = 'missing'`, never as 0. In the 2026-11-28 sample `rain` appeared in 5 of 48 hours.
- Not stored: `feels_like` (derived), `visibility`, `weather[]` text (kept in the raw payload only). No solar radiation is offered, so OpenWeather cannot feed the WBGT method.
- `source_issued_at` is empty (no model run time). Freshness counts from retrieval: `current` for 7 h (`PITCHY_FRESH_OPENWEATHER_HOURS`, DEC-04).
- The echoed `lat`/`lon` must be within 0.1° of the venue, else `SOURCE_RESPONSE_CHANGED`.

## Limits

- Group `openweather` in `registry.py`: at most one call per venue per 60 min (`PITCHY_OPENWEATHER_MIN_INTERVAL_MINUTES`), 15 min cool-down after an ordinary failure.
- `HTTP_401` (bad key, or One Call not active yet), `HTTP_403`, `HTTP_429` (daily cap; OpenWeather may block the account until the 00:00 UTC reset) are blocking codes: no retry before the 60 min gap.

## Failure cases

| Code | When |
| --- | --- |
| `NOT_CONFIGURED` | `OPENWEATHER_API_KEY` is empty. No request sent. |
| `TIMEOUT`, `NETWORK_ERROR`, `HTTP_<n>` | OpenWeather is unreachable or refuses the request. |
| `SOURCE_RESPONSE_CHANGED` | Not JSON, missing point or hourly data, wrong point, a missing required field, times off the hour or not 1 h apart. |

Tests and the captured sample (key removed; the body never had it): `backend/tests/sources/openweather/`.
