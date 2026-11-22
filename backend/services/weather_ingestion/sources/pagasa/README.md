# PAGASA adapter (panahon.gov.ph)

**Interim fallback** (DEC-02) until official PAGASA/DOST access is granted. Source ids:
- `pagasa_atmo`: PAGASA's ATMO AI model, about 2 km resolution, run every 6 h
- `pagasa_ecmwf`: ECMWF, as served by PAGASA, run every 12 h
- `pagasa`: official alerts and cyclone tracks

## How a run works (`session.py` → `forecast.py`)

1. `GET https://www.panahon.gov.ph/` with a fresh cookie jar, then read:
   - `<meta name="csrf-token">`: the `token` for API calls. It's the site's Laravel CSRF/session token and only valid with that visit's cookies.
   - `<meta name="nwp-runs">`: the latest run per model, e.g. `{"atmo":"…T18:00:00Z","ecmwf":"…T12:00:00Z"}`. This is the `init`.
2. For each venue and each model, `GET /api/v1/tiles/point/forecast?lat&lon&model&init&token`.
3. Everything (cookies, token) is discarded after the run. Nothing is stored, logged or sent to clients.

A new run always starts with a new visit, so rotating tokens and new model runs need no code change (FR-WTH-007, P-10).

## Forecast response → normalized values

| PAGASA field | Parameter code | Unit | Notes |
| --- | --- | --- | --- |
| `heat_index` | `heat_index` | °C (site legend; not stated in the response) | PAGASA's heat index. **Not WBGT.** |
| `accumulated_rain_1h` | `accumulated_rain_1h` | from `rain_unit`: ATMO `mm/h`, ECMWF `mm` | Exact meaning on ECMWF's 3 h/6 h steps still to confirm. Not mapped to Open-Meteo `precipitation` for that reason. |
| `wind_speed` | `wind_speed` | m/s (site legend) | Height not stated, so not mapped to `wind_speed_10m`. |
| `wind_direction` | `wind_direction` | ° | |
| `icon` | not stored as a value | text | Kept in the raw payload. |

- **Times are Philippine Time (UTC+8)** with no offset. They're converted to UTC. Guard: the first step must fall within 24 h after `init`. Observed: it equals `init`. If PAGASA switched to UTC strings, the guard fails instead of silently shifting by 8 h.
- **Uneven steps:** ATMO uses 15 min for the first 24 h, then 1 h. ECMWF uses 1 h, then 3 h, then 6 h. Each value is valid until the next step; the last one reuses the previous step length.
- `source_issued_at` = the model run (`init`).
- One model failing doesn't stop the other: each produces its own outcome.

## Alerts (`alerts.py`)

- `GET /api/v1/cap-alerts?token=`: nationwide official alerts. `NOTE` items are skipped, as on the site.
  - Times are PHT and converted to UTC.
  - Affected areas are listed with PSGC codes, so venues are matched by their municipality's PSGC code.
- **All alert text is reduced to plain text** (tags and scripts stripped). An observed `NOTE` headline contained a `<script>` tag. Never render alert text as HTML.
- `GET /api/v1/cyclone-track?token=`: `[]` when no cyclone is active. The active-cyclone format will be captured at the first real cyclone.
- Refresh: with every 6-hour run, and on open if last checked over 1 hour ago. At most hourly (DEC-02).

## Limits and etiquette

- Point forecasts: at most once every 4 hours per venue (FR-WTH-008), enforced by the ingestion runner from `source_fetches`.
- If PAGASA adds a login, a CAPTCHA, blocking, or terms that forbid this: stop and show Unavailable. **Do not work around it.**

## Failure codes

| Code | When |
| --- | --- |
| `PAGASA_LAYOUT_CHANGED` | Homepage no longer has `csrf-token` / `nwp-runs` |
| `SOURCE_RESPONSE_CHANGED` | Forecast/alert JSON differs from the above (fields, units, times) |
| `TIMEOUT`, `NETWORK_ERROR`, `HTTP_<n>` | Site unreachable or refusing (e.g. `HTTP_419` = expired session token) |

Tests and captured samples (token and cookies removed): `backend/tests/sources/pagasa/`.
