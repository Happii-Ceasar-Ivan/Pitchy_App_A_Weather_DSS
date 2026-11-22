-- Sprint B3: complete the venues' alert-matching codes (FR-SAF-007, P-07).
-- Codes confirmed by the team from the PSA PSGC list on 2026-11-22, in the 9-digit form that
-- PAGASA's alert data uses. A venue matches an alert if any of its codes appears in the alert.

-- Some venues sit in a sub-municipality (Manila's districts). PAGASA can name those directly.
alter table public.locations add column submunicipality_psgc_code text
  check (submunicipality_psgc_code ~ '^[0-9]{9}$');
comment on column public.locations.submunicipality_psgc_code is
  'PSGC code of the venue''s sub-municipality (e.g. a district of Manila), for alert matching.';

update public.locations
  set submunicipality_psgc_code = '133910000'  -- Malate (City of Manila)
  where scope_key = 'rizal_memorial';

update public.locations
  set psgc_code = '036904000'  -- Capas, Tarlac
  where scope_key = 'new_clark_city';
