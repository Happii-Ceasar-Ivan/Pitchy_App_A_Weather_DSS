-- Sprint B4 (team decision 2026-11-24, docs/decisions/venue-and-time.md): a match's age group
-- selects the heat level set in rules.yaml (senior 32 °C; AFC youth under-20 28 °C).
-- Adding a column breaks code that reads match_contexts with every column (class_row), so the
-- new backend image must be deployed right after this migration.

alter table public.match_contexts
  add column age_group text not null default 'senior'
  check (age_group in ('senior', 'youth_u20'));
comment on column public.match_contexts.age_group is
  'Competition age group chosen by the user: senior (default) or youth_u20 (AFC under-20 and younger).';
