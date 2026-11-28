-- P-30 (2026-11-28): OpenWeather One Call API 3.0 as a third forecast source, shown alongside
-- Open-Meteo and PAGASA. Display and citation only: not an input to the safety engine.
--
-- Added DISABLED. Enable it only after OPENWEATHER_API_KEY is set on pitchy-api and
-- pitchy-ingest:
--   update public.weather_sources set enabled = true where id = 'openweather';
-- Without the key the adapter sends no request and reports NOT_CONFIGURED.

insert into public.weather_sources (id, name, access_method, enabled, config_ref) values
  ('openweather', 'OpenWeather One Call 3.0', 'forecast_api', false, 'openweather')
on conflict (id) do nothing;
