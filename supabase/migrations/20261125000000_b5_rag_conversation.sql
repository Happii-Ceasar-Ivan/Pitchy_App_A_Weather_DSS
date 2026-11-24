-- Sprint B5 (docs/sprints/B5-plan.md, section 4.1). Team decisions 2026-11-24:
--   DEC-09 (docs/decisions/rag-storage.md): pgvector + full-text fallback in the same database;
--   DEC-14 (assessment-conversation-audit.md): one metadata-only row per question;
--   P-06 (access-protection.md): anonymous sessions; retention 30 days (user, 2026-11-24).
-- Adding columns breaks code that reads these tables with every column (class_row), so the new
-- backend image must be deployed right after this migration (as in B4).

-- pgvector. Supabase keeps extensions in the `extensions` schema.
create schema if not exists extensions;
create extension if not exists vector with schema extensions;
grant usage on schema extensions to pitchy_app;

-- Documents: a stable key matching rules.yaml source ids (e.g. fifa_ecm_2022), so chat references
-- line up with the assessment's sources.
alter table public.protocol_documents
  add column document_key text unique check (document_key ~ '^[a-z0-9_]+$');
comment on column public.protocol_documents.document_key is
  'Stable id matching a rules.yaml source id, e.g. fifa_ecm_2022.';

-- Chunks: section, embedding (Gemini, 768 dimensions) and a generated full-text column.
alter table public.protocol_chunks
  add column section text,
  add column embedding extensions.vector(768),
  add column embedding_model text,
  add column fts tsvector generated always as (to_tsvector('english', content)) stored,
  add constraint protocol_chunks_embedding_model_check
    check ((embedding is null) = (embedding_model is null));
comment on column public.protocol_chunks.embedding_model is
  'Model that made the embedding; set exactly when embedding is set.';

create index protocol_chunks_embedding_idx
  on public.protocol_chunks using hnsw (embedding extensions.vector_cosine_ops);
create index protocol_chunks_fts_idx on public.protocol_chunks using gin (fts);

-- The backend only reads documents; the loader script writes them with the admin connection.
revoke insert, update on table public.protocol_documents, public.protocol_chunks from pitchy_app;

-- One row per conversation question (DEC-14). Metadata only: no session id, question, answer
-- or IP address, so a row cannot be linked to a person or a session.
create table public.conversation_events (
  id                uuid primary key default gen_random_uuid(),
  occurred_at       timestamptz not null default now(),
  match_context_id  uuid not null references public.match_contexts (id),
  assessment_id     uuid references public.safety_assessments (id),
  role              text not null
    check (role in ('coach', 'match_official', 'referee', 'medical_staff', 'spectator')),
  generation        text not null check (generation in ('generated', 'unavailable')),
  outcome_code      text not null check (outcome_code ~ '^[A-Z][A-Z0-9_]*$'),
  provider_called   boolean not null default false,
  provider          text check (provider in ('gemini', 'groq', 'openrouter')),
  reference_keys    text[] not null default '{}',
  retrieval_mode    text check (retrieval_mode in ('hybrid', 'keyword_only', 'none')),
  duration_ms       integer check (duration_ms >= 0),
  check ((generation = 'generated') = (provider is not null)),
  check (provider is null or provider_called)
);
comment on table public.conversation_events is
  'DEC-14: metadata of each chatbot question. No session id, question, answer or IP.';
comment on column public.conversation_events.provider_called is
  'True when at least one AI provider was called; counts toward the daily AI cap.';
comment on column public.conversation_events.provider is
  'Provider whose answer was returned; null when no answer was generated.';
create index conversation_events_occurred_idx on public.conversation_events (occurred_at);

-- Access model R1.
alter table public.conversation_events enable row level security;
do $$
declare
  client_role text;
begin
  foreach client_role in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = client_role) then
      execute format('revoke all on table public.conversation_events from %I', client_role);
    end if;
  end loop;
end;
$$;
grant select, insert on table public.conversation_events to pitchy_app;
create policy pitchy_app_access on public.conversation_events
  for all to pitchy_app using (true) with check (true);

-- Retention (DEC-11 pattern, P-06): a second narrow function, so the weather one keeps its
-- signature. pitchy_app still has no DELETE privilege; it may only execute this function.
create function public.purge_old_conversation_data(keep interval)
returns table (conversation_events_deleted bigint, anonymous_sessions_deleted bigint)
language plpgsql
security definer
set search_path = ''
as $$
declare
  n_events bigint := 0;
  n_sessions bigint := 0;
begin
  if keep is null or keep < interval '1 day' then
    raise exception 'Retention period must be at least 1 day';
  end if;

  delete from public.conversation_events e where e.occurred_at < now() - keep;
  get diagnostics n_events = row_count;

  -- Sessions idle for the whole period (never used: counted from creation).
  delete from public.anonymous_sessions s
    where coalesce(s.last_request_at, s.created_at) < now() - keep;
  get diagnostics n_sessions = row_count;

  return query select n_events, n_sessions;
end;
$$;

comment on function public.purge_old_conversation_data(interval) is
  'P-06/DEC-14 retention (30 days). The only way the backend role can delete chat rows.';

revoke all on function public.purge_old_conversation_data(interval) from public;
do $$
declare
  client_role text;
begin
  foreach client_role in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = client_role) then
      execute format(
        'revoke all on function public.purge_old_conversation_data(interval) from %I',
        client_role
      );
    end if;
  end loop;
end;
$$;
grant execute on function public.purge_old_conversation_data(interval) to pitchy_app;
