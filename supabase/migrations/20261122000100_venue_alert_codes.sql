-- Alert matching codes for the venues (FR-SAF-007). PAGASA alerts list affected areas either per
-- municipality (psgc_code) or per province (geocode, "province_fallback"); a venue matches if
-- either of its codes appears. Codes use PSGC's 9-digit form as PAGASA's alert data does.
-- Verify against the PSA PSGC list; Capas' municipal code is left empty until confirmed.

alter table public.locations add column province_psgc_code text
  check (province_psgc_code ~ '^[0-9]{9}$');
comment on column public.locations.province_psgc_code is
  'PSGC code of the venue''s province (Metro Manila uses its regional code), for alert matching.';

update public.locations
  set psgc_code = '133900000',          -- City of Manila
      province_psgc_code = '130000000'  -- Metro Manila (code as used in PAGASA alerts)
  where scope_key = 'rizal_memorial';

update public.locations
  set province_psgc_code = '036900000'  -- Tarlac
  where scope_key = 'new_clark_city';
