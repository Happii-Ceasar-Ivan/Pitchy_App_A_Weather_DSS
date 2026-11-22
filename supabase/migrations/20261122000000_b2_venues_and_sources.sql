-- Sprint B2: the two prototype venues (P-07) and per-model PAGASA sources (DEC-02).
-- Reference data needed in every environment, so it lives in a migration, not the dev seed.

-- PSGC municipality code lets official alerts be matched to a venue (FR-SAF-007).
-- Filled from PAGASA's own alert data when a venue's municipality first appears there.
alter table public.locations add column psgc_code text check (psgc_code ~ '^[0-9]{9,10}$');
comment on column public.locations.psgc_code is
  'Philippine Standard Geographic Code of the venue''s city/municipality, for alert matching.';

insert into public.locations (scope_key, name, latitude, longitude) values
  ('rizal_memorial', 'Rizal Memorial Stadium, Manila', 14.563405271502504, 120.99193149681405),
  ('new_clark_city', 'New Clark City Athletics Stadium, Capas, Tarlac', 15.34571628739377, 120.53364718440237)
on conflict (scope_key) do nothing;

-- One source row per PAGASA model, so provenance shows which model produced a value.
-- The original 'pagasa' row stays as the source of official alerts and cyclone tracks.
insert into public.weather_sources (id, name, access_method, enabled, config_ref) values
  ('pagasa_atmo',  'PAGASA ATMO (panahon.gov.ph)',  'panahon_point_forecast', false, 'pagasa'),
  ('pagasa_ecmwf', 'PAGASA ECMWF (panahon.gov.ph)', 'panahon_point_forecast', false, 'pagasa'),
  ('open_meteo',   'Open-Meteo',                    'forecast_api',           false, 'open_meteo'),
  ('pagasa',       'PAGASA',                        'point_forecast_api',     false, 'pagasa'),
  ('dost_asti',    'DOST-ASTI',                     'undecided',              false, 'dost_asti')
on conflict (id) do nothing;

update public.weather_sources set access_method = 'forecast_api' where id = 'open_meteo';

-- Enabled together with their adapters (B2): Open-Meteo and both PAGASA models.
-- DOST-ASTI stays disabled until its feed is decided.
update public.weather_sources set enabled = true
  where id in ('open_meteo', 'pagasa_atmo', 'pagasa_ecmwf');
update public.weather_sources set name = 'PAGASA alerts (panahon.gov.ph)', access_method = 'panahon_alerts'
  where id = 'pagasa';
