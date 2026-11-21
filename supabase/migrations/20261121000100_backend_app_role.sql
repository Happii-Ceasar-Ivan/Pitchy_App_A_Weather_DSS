-- Least-privilege role for the FastAPI backend at runtime (R1, NFR-SEC-003, checklist: least privilege).
--
-- pitchy_app is NOLOGIN. A login role with a password is created outside migrations
-- (backend/scripts/create_db_login.py) so no password ever lives in Git, then granted pitchy_app.
-- Migrations keep running as the admin connection (SUPABASE_DB_URL); the app uses PITCHY_APP_DB_URL.
--
-- Because pitchy_app does not own the tables, RLS applies to it. Each table gets one explicit
-- policy for pitchy_app only; anon/authenticated still have no grants and no policies.
-- No DELETE is granted: retention/cleanup (DEC-11) will add narrowly scoped grants when decided.

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'pitchy_app') then
    create role pitchy_app nologin;
  end if;
end;
$$;

grant usage on schema public to pitchy_app;

do $$
declare
  t text;
begin
  foreach t in array array[
    'weather_sources', 'locations', 'match_contexts', 'ingestion_jobs', 'source_fetches',
    'forecast_values', 'safety_assessments', 'assessment_inputs', 'protocol_documents',
    'protocol_chunks', 'anonymous_sessions'
  ] loop
    execute format('grant select, insert, update on table public.%I to pitchy_app', t);
    execute format(
      'create policy pitchy_app_access on public.%I for all to pitchy_app using (true) with check (true)',
      t
    );
  end loop;
end;
$$;

grant usage on all sequences in schema public to pitchy_app;
grant execute on function public.set_updated_at() to pitchy_app;
