# Forecast relevance (Sprint B3)

Reads the shared cache only; never fetches. Data-quality rules, not safety decisions.

- `freshness.py`: per-source state for one match (DEC-04, P-05). Coverage first (kickoff → kickoff + 2 h, no gaps, from the newest successful fetch that covers it), then freshness: Open-Meteo by retrieval (7 h), PAGASA ATMO by model run (12 h), ECMWF by model run (24 h). States: `updating` (a job holds the lock), `current`, `stale`, `unavailable` (latest attempt failed and nothing covers), `missing`. A source without a rule is never `current`.
- `status.py`: all enabled sources for a venue, grouped by lock scope (`<group>:<venue>`), plus `ingestion_needed` (any stale/missing/unavailable) and `next_ingestion_at` (PAGASA's 4-hour gap, or 15 minutes after a failed attempt: DEC-04 option C).
- `consolidation.py`: P-09 view. Best **current** source per hour, else the best stale one marked stale; labelled fallback; range across comparable current sources (directions: smallest arc); never averaged across sources. ECMWF rain only on 1-hour steps until the 3 h/6 h meaning is confirmed.

All durations are settings (`PITCHY_MATCH_COVERAGE_HOURS`, `PITCHY_FRESH_*`, `PITCHY_RETRY_AFTER_FAILURE_MINUTES`). Tests: `tests/test_weather_api.py`, `tests/test_relevance_units.py`.
