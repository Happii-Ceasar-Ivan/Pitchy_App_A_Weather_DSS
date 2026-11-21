-- Pitchy initial schema (Sprint B1, DEC-08 Option A: normalized, one row per value).
--
-- Structure only: no thresholds, rule values, freshness durations or source domains are defined
-- here (DEC-03, DEC-04, DEC-05, DEC-06, P-11 stay open). All timestamps are timestamptz (UTC).
--
-- Access model R1: only the FastAPI backend talks to the database. RLS is enabled on every table
-- with NO policies, and anon/authenticated privileges are revoked, so Supabase client keys can
-- read or write nothing. Every new table in later migrations must do the same.

-- gen_random_uuid() is built in (PostgreSQL 13+); no extension needed.

-- updated_at maintenance -------------------------------------------------------------------------

create or replace function public.set_updated_at() returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- Weather sources (DEC-01) -----------------------------------------------------------------------

create table public.weather_sources (
  id             text primary key check (id ~ '^[a-z][a-z0-9_]{1,40}$'),
  name           text not null,
  access_method  text not null,
  enabled        boolean not null default false,
  config_ref     text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
comment on table public.weather_sources is 'Configured weather sources. config_ref names server-side config, never a secret.';

-- Locations / cache scope (shape depends on P-07) ------------------------------------------------

create table public.locations (
  id          uuid primary key default gen_random_uuid(),
  name        text,
  latitude    double precision not null check (latitude between -90 and 90),
  longitude   double precision not null check (longitude between -180 and 180),
  scope_key   text not null unique,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
comment on column public.locations.scope_key is 'Cache-scope key computed by the backend from the venue; granularity is OPEN (P-07).';

-- Match contexts (FR-MAT-001) --------------------------------------------------------------------

create table public.match_contexts (
  id             uuid primary key default gen_random_uuid(),
  kickoff_at     timestamptz not null,
  location_id    uuid not null references public.locations (id),
  venue_name     text,
  pitch_surface  text,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create index match_contexts_location_kickoff_idx on public.match_contexts (location_id, kickoff_at);

-- Ingestion jobs = shared lock (L1, FR-WTH-004, NFR-REL-002) -------------------------------------

create table public.ingestion_jobs (
  id                uuid primary key default gen_random_uuid(),
  scope_key         text not null,
  source_id         text not null references public.weather_sources (id),
  location_id       uuid not null references public.locations (id),
  state             text not null default 'queued'
                    check (state in ('queued', 'running', 'succeeded', 'failed', 'expired')),
  requested_at      timestamptz not null default now(),
  started_at        timestamptz,
  finished_at       timestamptz,
  lease_expires_at  timestamptz not null,
  failure_code      text,
  failure_message   text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  check ((state in ('succeeded', 'failed', 'expired')) = (finished_at is not null))
);
comment on table public.ingestion_jobs is
  'One row per ingestion attempt for one (source, location) scope. The partial unique index below is the lock.';

-- The lock: at most one active job per scope. A second insert for the same scope fails atomically.
create unique index ingestion_jobs_one_active_per_scope
  on public.ingestion_jobs (scope_key)
  where state in ('queued', 'running');
create index ingestion_jobs_scope_recent_idx on public.ingestion_jobs (scope_key, requested_at desc);
create index ingestion_jobs_active_lease_idx on public.ingestion_jobs (lease_expires_at)
  where state in ('queued', 'running');

-- Source fetches: one row per call to a source, with raw provenance (FR-WTH-005) -----------------

create table public.source_fetches (
  id                  uuid primary key default gen_random_uuid(),
  source_id           text not null references public.weather_sources (id),
  location_id         uuid not null references public.locations (id),
  ingestion_job_id    uuid references public.ingestion_jobs (id),
  requested_at        timestamptz not null default now(),
  completed_at        timestamptz,
  status              text not null check (status in ('succeeded', 'failed')),
  error_code          text,
  error_summary       text,
  source_issued_at    timestamptz,
  raw_content_type    text,
  raw_payload         text,
  raw_payload_sha256  text check (raw_payload_sha256 ~ '^[0-9a-f]{64}$'),
  created_at          timestamptz not null default now()
);
comment on column public.source_fetches.raw_payload is
  'Raw source response for provenance and parser debugging. Never contains request tokens. Retention: DEC-11.';
create index source_fetches_source_location_idx
  on public.source_fetches (source_id, location_id, requested_at desc);

-- Forecast values: one row per parameter per time slot (NFR-DAT-001) -----------------------------

create table public.forecast_values (
  id                    bigint generated always as identity primary key,
  fetch_id              uuid not null references public.source_fetches (id),
  source_id             text not null references public.weather_sources (id),
  location_id           uuid not null references public.locations (id),
  parameter             text not null,
  value                 double precision,
  unit                  text,
  value_state           text not null default 'ok' check (value_state in ('ok', 'missing', 'invalid')),
  retrieved_at          timestamptz not null,
  forecast_valid_from   timestamptz,
  forecast_valid_until  timestamptz,
  expires_at            timestamptz,
  created_at            timestamptz not null default now(),
  check (value_state <> 'ok' or value is not null),
  check (forecast_valid_until is null or forecast_valid_from is null
         or forecast_valid_until >= forecast_valid_from)
);
comment on column public.forecast_values.parameter is 'Parameter code; the parameter list is OPEN (DEC-03).';
-- Match-time coverage lookups (FR-MAT-002, FR-WTH-003).
create index forecast_values_coverage_idx
  on public.forecast_values (location_id, parameter, forecast_valid_from, forecast_valid_until);
-- Latest values per source/location (freshness checks).
create index forecast_values_source_latest_idx
  on public.forecast_values (source_id, location_id, retrieved_at desc);
create index forecast_values_fetch_idx on public.forecast_values (fetch_id);

-- Safety assessments (FR-SAF-005, NFR-AUD-001) ---------------------------------------------------

create table public.safety_assessments (
  id                uuid primary key default gen_random_uuid(),
  match_context_id  uuid not null references public.match_contexts (id),
  assessed_at       timestamptz not null default now(),
  rule_version      text not null,
  result            jsonb not null,
  limitations       jsonb not null default '[]'::jsonb,
  created_at        timestamptz not null default now()
);
comment on column public.safety_assessments.result is
  'Deterministic engine output snapshot (indicators, classifications, notices) as returned by the API.';
create index safety_assessments_match_idx on public.safety_assessments (match_context_id, assessed_at desc);

-- Exact inputs used by each assessment. ON DELETE RESTRICT keeps audited inputs from being cleaned up.
create table public.assessment_inputs (
  assessment_id      uuid not null references public.safety_assessments (id) on delete cascade,
  forecast_value_id  bigint not null references public.forecast_values (id) on delete restrict,
  hazard             text not null check (hazard in ('heat', 'lightning', 'rainfall')),
  primary key (assessment_id, forecast_value_id, hazard)
);
create index assessment_inputs_value_idx on public.assessment_inputs (forecast_value_id);

-- Approved protocol documents for RAG (B5-1; embeddings wait for DEC-09) -------------------------

create table public.protocol_documents (
  id               uuid primary key default gen_random_uuid(),
  title            text not null,
  authority        text not null,
  version          text not null,
  published_on     date,
  scope            text,
  jurisdiction     text,
  approval_status  text not null default 'draft' check (approval_status in ('draft', 'approved', 'retired')),
  source_uri       text,
  reviewed_at      timestamptz,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  unique (title, authority, version)
);

create table public.protocol_chunks (
  id           uuid primary key default gen_random_uuid(),
  document_id  uuid not null references public.protocol_documents (id) on delete cascade,
  position     integer not null check (position >= 0),
  content      text not null,
  created_at   timestamptz not null default now(),
  unique (document_id, position)
);

-- Anonymous chatbot sessions (P-06). No questions, answers or raw IP addresses. ------------------

create table public.anonymous_sessions (
  id                     uuid primary key default gen_random_uuid(),
  token_hash             bytea not null unique check (octet_length(token_hash) = 32),
  counted_prompt_times   timestamptz[] not null default '{}',
  cooldown_until         timestamptz,
  last_request_at        timestamptz,
  created_at             timestamptz not null default now(),
  updated_at             timestamptz not null default now()
);
comment on column public.anonymous_sessions.token_hash is 'HMAC-SHA256 of the session token with a server secret.';
create index anonymous_sessions_last_request_idx on public.anonymous_sessions (last_request_at);

-- updated_at triggers ----------------------------------------------------------------------------

create trigger weather_sources_updated_at before update on public.weather_sources
  for each row execute function public.set_updated_at();
create trigger locations_updated_at before update on public.locations
  for each row execute function public.set_updated_at();
create trigger match_contexts_updated_at before update on public.match_contexts
  for each row execute function public.set_updated_at();
create trigger ingestion_jobs_updated_at before update on public.ingestion_jobs
  for each row execute function public.set_updated_at();
create trigger protocol_documents_updated_at before update on public.protocol_documents
  for each row execute function public.set_updated_at();
create trigger anonymous_sessions_updated_at before update on public.anonymous_sessions
  for each row execute function public.set_updated_at();

-- Access control (R1, NFR-SEC-003) ---------------------------------------------------------------

do $$
declare
  t text;
  client_role text;
begin
  foreach t in array array[
    'weather_sources', 'locations', 'match_contexts', 'ingestion_jobs', 'source_fetches',
    'forecast_values', 'safety_assessments', 'assessment_inputs', 'protocol_documents',
    'protocol_chunks', 'anonymous_sessions'
  ] loop
    -- ENABLE (not FORCE): the backend connects as the table owner and is not subject to RLS.
    execute format('alter table public.%I enable row level security', t);
    foreach client_role in array array['anon', 'authenticated'] loop
      if exists (select 1 from pg_roles where rolname = client_role) then
        execute format('revoke all on table public.%I from %I', t, client_role);
      end if;
    end loop;
  end loop;

  foreach client_role in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = client_role) then
      execute format('revoke all on function public.set_updated_at() from %I', client_role);
      execute format('revoke usage, select on all sequences in schema public from %I', client_role);
    end if;
  end loop;
end;
$$;
