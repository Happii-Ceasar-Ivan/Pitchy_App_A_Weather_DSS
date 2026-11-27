-- P-27 A2 (user decision 2026-11-28): a PAGASA run check that found no newer model run is stored
-- as 'unchanged'. Such a row records that PAGASA was asked (it counts for the FR-WTH-008 gap) and
-- which run it listed. It has no values and no payload; freshness and coverage read only
-- 'succeeded' rows. Every existing row is 'succeeded' or 'failed', so both checks hold for it.

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'public.source_fetches'::regclass and conname = 'source_fetches_status_check'
  ) then
    raise exception 'source_fetches_status_check not found; check the constraint name first';
  end if;
end $$;

alter table public.source_fetches drop constraint source_fetches_status_check;
alter table public.source_fetches add constraint source_fetches_status_check
  check (status in ('succeeded', 'failed', 'unchanged'));

-- An 'unchanged' row always names the run PAGASA listed and carries no error or payload.
alter table public.source_fetches add constraint source_fetches_unchanged_shape
  check (status <> 'unchanged'
         or (source_issued_at is not null and error_code is null and error_summary is null
             and raw_content_type is null and raw_payload is null and raw_payload_sha256 is null));

comment on column public.source_fetches.status is
  'succeeded: values stored. failed: error_code set. unchanged: PAGASA listed no newer run than '
  'the stored one, so no forecast was downloaded (P-27 A2); counts for the FR-WTH-008 gap.';
