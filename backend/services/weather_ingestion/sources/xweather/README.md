# Vaisala Xweather: live lightning (DEC-06, 2026-11-23)

Free **Developer** plan: 15,000 accesses/month, 100 requests/min; it pauses at the limit and resets monthly.
- **Non-commercial use only** (Vaisala terms §17.1).
- **Credit:** show **"Powered by Vaisala Xweather"** linking to https://www.xweather.com/ (or the unmodified Xweather logo) wherever the data appears.
- **Keys:** `XWEATHER_CLIENT_ID` / `XWEATHER_CLIENT_SECRET` in the root `.env` (dev account) or Azure secrets (presentation account). They travel as query parameters, so **never log request URLs**.

## Request

`GET https://data.api.xweather.com/lightning/flash/closest?p=<lat>,<lon>&radius=40km&limit=1000&client_id=…&client_secret=…`

- Covers the **past 5 minutes**, at most **40 km** radius and 1,000 flashes per query. Global coverage.
- **Cost:** 1 access per call. Measured 2026-11-23 from the response headers: `x-cost-tokens: 1`, `x-cost-endpoint: lightning_flash`.

## Normalization (`lightning.py`)

- Each flash: `ob.timestamp` (Unix, UTC) and `loc.lat` / `loc.long`. The response has no distance, so Pitchy computes the **great-circle distance** to the venue (haversine). Flashes are sorted nearest first.
- `success: true` with `warn_no_data` = nothing detected (a valid, empty reading).
- `success: false` → `XWEATHER_<CODE>` (e.g. bad keys).
- Any other warning that comes with data, or changed fields → `SOURCE_RESPONSE_CHANGED`. Nothing is guessed.
- The flash type (cloud-to-ground vs in-cloud) and peak current are **not** documented for this endpoint, so they aren't used.

## Use in Pitchy

- **On demand only:** from 2 hours before kickoff to the end of the coverage window, when someone opens the match's lightning view.
- **Shared:** one check per venue at most every 5 minutes (lock scope `xweather_lightning:<venue>`), so many users cost one call.
- The AFC 30/30 procedure (`rules.yaml`) is shown as official guidance when lightning is detected or a PAGASA thunderstorm alert covers the venue. Pitchy never declares "stop play"; officials judge it on site.

## Failure codes

| Code | When |
| --- | --- |
| `NOT_CONFIGURED` | Keys missing |
| `TIMEOUT`, `NETWORK_ERROR`, `HTTP_<n>` | Unreachable / refused |
| `XWEATHER_<CODE>` | Xweather answered `success: false` |
| `SOURCE_RESPONSE_CHANGED` | Not JSON, or fields changed |

## Tests and samples

`backend/tests/sources/xweather/`:
- a **real** empty response for Rizal Memorial (2026-11-23);
- a sample shaped like the documented example (positions near Rizal; **not** real detections).

Capture a real non-empty sample at the first storm.
