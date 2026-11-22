# Approved Source Allowlist

Explicitly approved weather-source hosts, enforced in code by `hosts.py` (SSRF prevention). Adapters can only make requests through `AllowlistedClient`, which refuses any other host, requires HTTPS and does not follow redirects. No user-supplied URLs are fetched.

| Host | Source | Approved |
| --- | --- | --- |
| `api.open-meteo.com` | Open-Meteo Forecast API | Team, 2026-11-22 (DEC-01) |
| `www.panahon.gov.ph` | PAGASA point forecast, alerts, cyclone track (interim fallback) | Team, 2026-11-21 (DEC-02) |

DOST-ASTI will be added once its feed is decided.
