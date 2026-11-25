-- B6 item 6: the shared daily AI question cap (P-06) can no longer overshoot.
--
-- Before: the cap counted conversation_events, which are written after the AI call, so every
-- request in flight saw the same count. Now each question reserves a slot in this table, under
-- a row lock, before any provider is called. A slot is given back when no provider was called.
-- One row per Manila day (fixed UTC+8). Aggregate counts only: no session, IP or question text.

create table public.chat_daily_ai_usage (
  day         date primary key,
  reserved    integer not null default 0 check (reserved >= 0),
  updated_at  timestamptz not null default now()
);
comment on table public.chat_daily_ai_usage is
  'Daily AI question slots reserved before provider calls (B6). One row per Manila day.';
comment on column public.chat_daily_ai_usage.reserved is
  'Questions that called, or are calling, an AI provider on this day. Compared with the cap.';

-- Access model R1.
alter table public.chat_daily_ai_usage enable row level security;
do $$
declare
  client_role text;
begin
  foreach client_role in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = client_role) then
      execute format('revoke all on table public.chat_daily_ai_usage from %I', client_role);
    end if;
  end loop;
end;
$$;
grant select, insert, update on table public.chat_daily_ai_usage to pitchy_app;
create policy pitchy_app_access on public.chat_daily_ai_usage
  for all to pitchy_app using (true) with check (true);
