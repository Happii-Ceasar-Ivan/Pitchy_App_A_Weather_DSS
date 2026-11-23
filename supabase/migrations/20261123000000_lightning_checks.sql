-- DEC-06 (team decision 2026-11-23): live lightning detection from Vaisala Xweather.
-- One row per check of one venue (lock scope 'xweather_lightning:<venue>', at most every few
-- minutes, shared by all users). Data is real-time detection of the past 5 minutes, not a
-- forecast. Flashes are stored as returned (time, position) plus the distance Pitchy computed.

insert into public.weather_sources (id, name, access_method, enabled, config_ref) values
  ('xweather_lightning', 'Vaisala Xweather lightning', 'lightning_flash_api', true, 'xweather')
on conflict (id) do nothing;

create table public.lightning_checks (
  id                uuid primary key default gen_random_uuid(),
  location_id       uuid not null references public.locations (id),
  ingestion_job_id  uuid references public.ingestion_jobs (id),
  checked_at        timestamptz not null default now(),
  status            text not null check (status in ('succeeded', 'failed')),
  error_code        text,
  error_summary     text,
  radius_km         double precision check (radius_km > 0),
  flash_count       integer check (flash_count >= 0),
  nearest_km        double precision check (nearest_km >= 0),
  latest_flash_at   timestamptz,
  flashes           jsonb not null default '[]'::jsonb,
  raw_payload       text,
  raw_payload_sha256 text check (raw_payload_sha256 ~ '^[0-9a-f]{64}$'),
  created_at        timestamptz not null default now(),
  check ((status = 'failed') = (error_code is not null))
);
comment on table public.lightning_checks is
  'Live lightning detection near a venue (Vaisala Xweather lightning/flash, past 5 minutes).';
create index lightning_checks_location_recent_idx
  on public.lightning_checks (location_id, checked_at desc);

-- Access model R1.
alter table public.lightning_checks enable row level security;
do $$
declare
  client_role text;
begin
  foreach client_role in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = client_role) then
      execute format('revoke all on table public.lightning_checks from %I', client_role);
    end if;
  end loop;
end;
$$;
grant select, insert on table public.lightning_checks to pitchy_app;
create policy pitchy_app_access on public.lightning_checks
  for all to pitchy_app using (true) with check (true);

-- Retention (DEC-11): lightning checks rotate with forecasts (14 days), keeping the newest per
-- venue. The return type gains a column, so the function is recreated.
drop function public.purge_old_weather_data(interval, interval);

create function public.purge_old_weather_data(
  keep_forecasts interval,
  keep_jobs interval
)
returns table (
  forecast_values_deleted bigint,
  source_fetches_deleted bigint,
  official_alerts_deleted bigint,
  alert_checks_deleted bigint,
  lightning_checks_deleted bigint,
  ingestion_jobs_deleted bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  n_values bigint := 0;
  n_fetches bigint := 0;
  n_alerts bigint := 0;
  n_checks bigint := 0;
  n_lightning bigint := 0;
  n_jobs bigint := 0;
  keep_ids uuid[];
  old_ids uuid[];
begin
  if keep_forecasts is null or keep_jobs is null
     or keep_forecasts < interval '1 day' or keep_jobs < interval '1 day' then
    raise exception 'Retention periods must be at least 1 day';
  end if;

  -- Fetches that must stay.
  keep_ids := array(
    (select distinct on (source_id, location_id) id from public.source_fetches
       where status = 'succeeded' order by source_id, location_id, requested_at desc)
    union
    (select distinct on (source_id, location_id) id from public.source_fetches
       order by source_id, location_id, requested_at desc)
    union
    (select v.fetch_id from public.assessment_inputs ai
       join public.forecast_values v on v.id = ai.forecast_value_id)
  );
  old_ids := array(
    select f.id from public.source_fetches f
      where f.requested_at < now() - keep_forecasts and f.id <> all (keep_ids)
  );

  delete from public.forecast_values v
    where v.fetch_id = any (old_ids)
      and not exists (select 1 from public.assessment_inputs ai where ai.forecast_value_id = v.id);
  get diagnostics n_values = row_count;

  delete from public.source_fetches f
    where f.id = any (old_ids)
      and not exists (select 1 from public.forecast_values v where v.fetch_id = f.id);
  get diagnostics n_fetches = row_count;

  -- Alert checks: keep the newest one and the newest successful one.
  old_ids := array(
    select c.id from public.alert_checks c
      where c.checked_at < now() - keep_jobs
        and c.id <> all (array(
          (select id from public.alert_checks order by checked_at desc limit 1)
          union
          (select id from public.alert_checks where status = 'succeeded'
             order by checked_at desc limit 1)
        ))
  );
  delete from public.official_alerts a where a.check_id = any (old_ids);
  get diagnostics n_alerts = row_count;
  delete from public.alert_checks c where c.id = any (old_ids);
  get diagnostics n_checks = row_count;

  -- Lightning checks: keep the newest per venue.
  delete from public.lightning_checks l
    where l.checked_at < now() - keep_forecasts
      and l.id <> all (array(
        select distinct on (location_id) id from public.lightning_checks
          order by location_id, checked_at desc
      ));
  get diagnostics n_lightning = row_count;

  -- Finished jobs nothing refers to any more. Active jobs (the lock) are never touched.
  delete from public.ingestion_jobs j
    where j.state in ('succeeded', 'failed', 'expired')
      and j.requested_at < now() - keep_jobs
      and not exists (select 1 from public.source_fetches f where f.ingestion_job_id = j.id)
      and not exists (select 1 from public.alert_checks c where c.ingestion_job_id = j.id)
      and not exists (select 1 from public.lightning_checks l where l.ingestion_job_id = j.id);
  get diagnostics n_jobs = row_count;

  return query select n_values, n_fetches, n_alerts, n_checks, n_lightning, n_jobs;
end;
$$;

comment on function public.purge_old_weather_data(interval, interval) is
  'DEC-11 retention. Called by the ingest job; the only way the backend role can delete rows.';

revoke all on function public.purge_old_weather_data(interval, interval) from public;
do $$
declare
  client_role text;
begin
  foreach client_role in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = client_role) then
      execute format(
        'revoke all on function public.purge_old_weather_data(interval, interval) from %I',
        client_role
      );
    end if;
  end loop;
end;
$$;
grant execute on function public.purge_old_weather_data(interval, interval) to pitchy_app;
