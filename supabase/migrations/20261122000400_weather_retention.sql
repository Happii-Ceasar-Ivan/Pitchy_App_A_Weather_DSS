-- DEC-11 (team decision 2026-11-22): rotate weather data after 14 days; jobs and alert checks
-- after 30. The ingest job calls this function after each run. pitchy_app still has no DELETE
-- privilege: it may only execute this one function, which runs as its owner (SECURITY DEFINER).
--
-- Never deleted: the newest successful fetch and the newest attempt per (source, venue); the
-- newest alert check and newest successful one; any value used by a safety assessment
-- (assessment_inputs, FR-SAF-005) and the fetch/job it belongs to.

create or replace function public.purge_old_weather_data(
  keep_forecasts interval,
  keep_jobs interval
)
returns table (
  forecast_values_deleted bigint,
  source_fetches_deleted bigint,
  official_alerts_deleted bigint,
  alert_checks_deleted bigint,
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

  -- Finished jobs nothing refers to any more. Active jobs (the lock) are never touched.
  delete from public.ingestion_jobs j
    where j.state in ('succeeded', 'failed', 'expired')
      and j.requested_at < now() - keep_jobs
      and not exists (select 1 from public.source_fetches f where f.ingestion_job_id = j.id)
      and not exists (select 1 from public.alert_checks c where c.ingestion_job_id = j.id);
  get diagnostics n_jobs = row_count;

  return query select n_values, n_fetches, n_alerts, n_checks, n_jobs;
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
