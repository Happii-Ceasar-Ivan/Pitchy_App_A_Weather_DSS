# DOST-ASTI adapter (placeholder)

Source id: `dost_asti`. **Disabled.** The team is waiting on official access (an adviser-signed request letter). Until then, `adapter.py` always reports `NOT_CONFIGURED`, and the app shows DOST-ASTI as Unavailable.

When the feed is decided:
1. Add its host to `../allowlist/hosts.py` and `../allowlist/README.md`.
2. Implement `fetch()` following `../open_meteo/adapter.py`, and record the endpoints, fields, units and time zone here.
3. Add captured samples and parser tests under `backend/tests/sources/dost_asti/`.
4. Enable the `dost_asti` row in `weather_sources`.
