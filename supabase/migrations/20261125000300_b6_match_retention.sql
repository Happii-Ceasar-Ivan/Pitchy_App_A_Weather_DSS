-- B6 item 8: match and assessment retention (DEC-14 addendum, user 2026-11-25).
--
-- A match context and everything saved for it is kept for 4.5 months (135 days, the setting
-- PITCHY_RETENTION_MATCH_DAYS) after kickoff, then deleted by the ingest run. Matches hold no
-- personal data. Deleting an assessment also frees the weather values it pinned (DEC-11), so
-- purge_old_weather_data can rotate them later.
--
-- The backend role has no DELETE privilege: this narrow function is the only way it can remove
-- these rows. Order: chat events, then assessments (assessment_inputs cascade), then matches.

create function public.purge_old_match_contexts(keep interval)
returns table (
  conversation_events_deleted bigint,
  safety_assessments_deleted bigint,
  match_contexts_deleted bigint
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  n_events bigint := 0;
  n_assessments bigint := 0;
  n_matches bigint := 0;
begin
  -- A guard against a wrong setting: never delete a match that kicked off within 30 days.
  if keep is null or keep < interval '30 days' then
    raise exception 'Match retention period must be at least 30 days';
  end if;

  -- now() is fixed for the whole transaction, so every step selects the same matches.
  delete from public.conversation_events e
    where e.match_context_id in (select m.id from public.match_contexts m
                                 where m.kickoff_at < now() - keep);
  get diagnostics n_events = row_count;

  delete from public.safety_assessments a
    where a.match_context_id in (select m.id from public.match_contexts m
                                 where m.kickoff_at < now() - keep);
  get diagnostics n_assessments = row_count;

  delete from public.match_contexts m where m.kickoff_at < now() - keep;
  get diagnostics n_matches = row_count;

  return query select n_events, n_assessments, n_matches;
end;
$$;

comment on function public.purge_old_match_contexts(interval) is
  'B6/DEC-14: deletes matches whose kickoff is older than keep (135 days), with their '
  'assessments, assessment inputs and chat events. Refuses periods under 30 days.';

revoke all on function public.purge_old_match_contexts(interval) from public;
do $$
declare
  client_role text;
begin
  foreach client_role in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = client_role) then
      execute format('revoke all on function public.purge_old_match_contexts(interval) from %I',
                     client_role);
    end if;
  end loop;
end;
$$;
grant execute on function public.purge_old_match_contexts(interval) to pitchy_app;
