-- Sprint B3: store PAGASA official alerts (FR-SAF-007, DEC-02, DEC-04).
-- One nationwide check at most hourly (lock scope 'pagasa_alerts'): every check is a row, and the
-- alerts it returned are stored with it. The current alerts are those of the latest successful
-- check. Alert text is untrusted source text, already reduced to plain text; never render as HTML.
-- Retention is OPEN (DEC-11); no DELETE is granted.

-- The alerts job is nationwide, so it has no venue.
alter table public.ingestion_jobs alter column location_id drop not null;
alter table public.ingestion_jobs add constraint ingestion_jobs_location_required
  check (location_id is not null or scope_key = 'pagasa_alerts');

create table public.alert_checks (
  id               uuid primary key default gen_random_uuid(),
  ingestion_job_id uuid references public.ingestion_jobs (id),
  checked_at       timestamptz not null default now(),
  status           text not null check (status in ('succeeded', 'failed')),
  error_code       text,
  error_summary    text,
  active_cyclones  integer check (active_cyclones >= 0),
  alert_count      integer check (alert_count >= 0),
  created_at       timestamptz not null default now(),
  check ((status = 'failed') = (error_code is not null))
);
comment on table public.alert_checks is 'One row per nationwide PAGASA alerts request (at most hourly).';
create index alert_checks_recent_idx on public.alert_checks (checked_at desc);

create table public.official_alerts (
  id              uuid primary key default gen_random_uuid(),
  check_id        uuid not null references public.alert_checks (id),
  identifier      text not null,
  issuer          text not null,
  event           text not null,
  subtype         text not null,
  headline        text not null,
  message         text not null,
  issued_at       timestamptz,
  valid_until     timestamptz,
  areas           jsonb not null default '[]'::jsonb,
  matched_venues  text[] not null default '{}',
  created_at      timestamptz not null default now()
);
comment on column public.official_alerts.areas is
  'Affected areas as issued: municipality, province, 9-digit PSGC code, level, relation (plain text).';
comment on column public.official_alerts.matched_venues is
  'Venue scope keys whose alert codes appear in areas, when the check ran.';
create index official_alerts_check_idx on public.official_alerts (check_id);

-- Access model R1: RLS on, no client access, one policy for the backend role.
do $$
declare
  t text;
  client_role text;
begin
  foreach t in array array['alert_checks', 'official_alerts'] loop
    execute format('alter table public.%I enable row level security', t);
    foreach client_role in array array['anon', 'authenticated'] loop
      if exists (select 1 from pg_roles where rolname = client_role) then
        execute format('revoke all on table public.%I from %I', t, client_role);
      end if;
    end loop;
    execute format('grant select, insert on table public.%I to pitchy_app', t);
    execute format(
      'create policy pitchy_app_access on public.%I for all to pitchy_app using (true) with check (true)',
      t
    );
  end loop;
end;
$$;
