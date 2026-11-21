-- Development seed: non-sensitive fixtures only (Sprint B1-3). Never run against production.
-- Sources follow DEC-01 (PAGASA, Open-Meteo, DOST-ASTI). All start disabled; an adapter is enabled
-- only once it is implemented and tested (Sprint B2). Exact Open-Meteo and DOST-ASTI feeds are OPEN.

insert into public.weather_sources (id, name, access_method, enabled, config_ref) values
  ('pagasa',     'PAGASA',     'point_forecast_api', false, 'pagasa'),
  ('open_meteo', 'Open-Meteo', 'undecided',          false, 'open_meteo'),
  ('dost_asti',  'DOST-ASTI',  'undecided',          false, 'dost_asti')
on conflict (id) do nothing;
