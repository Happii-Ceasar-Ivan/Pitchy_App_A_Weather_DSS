-- B6: shared per-IP request limits (P-06 hardening; values approved by the user 2026-11-25).
--
-- One row per (route scope, hashed client IP) holding the request times inside the current
-- window. Shared by every API replica and kept across restarts. The raw IP is never stored:
-- ip_key is an HMAC-SHA256 of the IP with a server secret (NFR-PRIV-001).

create table public.ip_rate_limits (
  scope       text not null check (scope ~ '^[a-z_]{1,40}$'),
  ip_key      bytea not null check (octet_length(ip_key) = 32),
  hit_times   timestamptz[] not null default '{}',
  updated_at  timestamptz not null default now(),
  primary key (scope, ip_key)
);
comment on table public.ip_rate_limits is
  'Per-IP request limits (B6). Hashed IP only; rows are purged after a day of no requests.';
comment on column public.ip_rate_limits.ip_key is
  'HMAC-SHA256 of the client IP with a server secret. Never the raw IP.';
comment on column public.ip_rate_limits.hit_times is
  'Database-clock times of the counted requests inside the scope''s window (oldest first).';
create index ip_rate_limits_updated_idx on public.ip_rate_limits (updated_at);

-- Access model R1.
alter table public.ip_rate_limits enable row level security;
do $$
declare
  client_role text;
begin
  foreach client_role in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = client_role) then
      execute format('revoke all on table public.ip_rate_limits from %I', client_role);
    end if;
  end loop;
end;
$$;
grant select, insert, update on table public.ip_rate_limits to pitchy_app;
create policy pitchy_app_access on public.ip_rate_limits
  for all to pitchy_app using (true) with check (true);

-- Retention: a narrow function is the only way the backend role can delete these rows.
create function public.purge_old_ip_rate_limits()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  n_rows bigint := 0;
begin
  delete from public.ip_rate_limits r where r.updated_at < now() - interval '1 day';
  get diagnostics n_rows = row_count;
  return n_rows;
end;
$$;

comment on function public.purge_old_ip_rate_limits() is
  'B6: deletes per-IP limit rows idle for more than a day (every window is 1 hour or less).';

revoke all on function public.purge_old_ip_rate_limits() from public;
do $$
declare
  client_role text;
begin
  foreach client_role in array array['anon', 'authenticated'] loop
    if exists (select 1 from pg_roles where rolname = client_role) then
      execute format('revoke all on function public.purge_old_ip_rate_limits() from %I',
                     client_role);
    end if;
  end loop;
end;
$$;
grant execute on function public.purge_old_ip_rate_limits() to pitchy_app;
