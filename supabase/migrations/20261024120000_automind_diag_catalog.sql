-- =============================================================================
-- AutoMind AI — controller / profile diagnostic catalogue (part 3)
--
-- Two tables:
--   * diag_controller_catalog — reference data. UNVERIFIED static identifiers
--     (module-group names per manufacturer, seeded from
--     shared/diag/controller_identifiers.json). Readable by every signed-in user;
--     written only by migrations (the schema owner). These are NOT CAN addresses
--     and NOT proof that an ECU is readable.
--   * diag_ecu_profiles — candidate ECU access profiles (protocol + headers).
--     UNVERIFIED by default; a profile is never field-trusted until a platform
--     admin APPROVES it with evidence (mirrors the modules.json verified:false
--     philosophy and the obd_devices certification guard). Submit/approve is
--     platform-admin only; a non-admin can never set an approved status.
--
-- Idempotent: guarded so a re-run does not error.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- diag_controller_catalog (reference data)
-- -----------------------------------------------------------------------------
create table if not exists automind.diag_controller_catalog (
  id                  text primary key check (id ~ '^[a-z0-9][a-z0-9_]*$'),
  make                text not null check (length(trim(make)) > 0),
  category            text not null check (length(trim(category)) > 0),
  label               text,
  -- Static identifiers are, and stay, unverified: a real profile lives in
  -- diag_ecu_profiles. Keep the column for a uniform API shape.
  verification_status text not null default 'unverified' check (verification_status in ('unverified')),
  source_type         text default 'static_identifier',
  source_reference    text,
  created_at          timestamptz not null default now()
);
create index if not exists diag_controller_catalog_make_idx on automind.diag_controller_catalog (make);
comment on table automind.diag_controller_catalog is
  'UNVERIFIED static controller identifiers (module-group names); not CAN addresses, not readable-ECU proof.';

-- -----------------------------------------------------------------------------
-- diag_ecu_profiles (candidate access profiles, admin-curated)
-- -----------------------------------------------------------------------------
create table if not exists automind.diag_ecu_profiles (
  id                  uuid primary key default gen_random_uuid(),
  make                text not null check (length(trim(make)) > 0),
  model               text,
  market              text,
  variant             text,
  year_from           smallint check (year_from between 1980 and 2100),
  year_to             smallint check (year_to between 1980 and 2100),
  controller_id       text references automind.diag_controller_catalog(id) on delete set null,
  protocol            text,
  tx_header           text,
  rx_header           text,
  read_request        text,
  id_bits             smallint check (id_bits in (11, 29)),
  category            text,
  verification_status text not null default 'unverified'
                      check (verification_status in (
                        'unverified', 'verified_vehicle_trace', 'licensed_oem',
                        'standard_specification', 'demo_only', 'rejected')),
  source_type         text,
  source_reference    text,
  model_year_range    text,
  notes               text,
  submitted_by        uuid references automind.users(id) on delete set null,
  reviewed_by         uuid references automind.users(id) on delete set null,
  reviewed_at         timestamptz,
  version             integer not null default 1 check (version >= 1),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint diag_ecu_profiles_years check (year_from is null or year_to is null or year_from <= year_to)
);
create index if not exists diag_ecu_profiles_lookup_idx
  on automind.diag_ecu_profiles (make, model, year_from, year_to);
create index if not exists diag_ecu_profiles_pending_idx
  on automind.diag_ecu_profiles (verification_status);

drop trigger if exists diag_ecu_profiles_set_updated_at on automind.diag_ecu_profiles;
create trigger diag_ecu_profiles_set_updated_at before update on automind.diag_ecu_profiles
  for each row execute function automind.set_updated_at();

-- Defence in depth on top of the admin-only write policies below: a non-admin
-- can never move a profile into an approved verification_status.
create or replace function automind.guard_diag_profile_status()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user = 'automind_app' and not automind.is_platform_admin()
     and new.verification_status in ('verified_vehicle_trace', 'licensed_oem', 'standard_specification') then
    raise exception 'profile approval requires platform admin' using errcode = '42501';
  end if;
  return new;
end;
$$;
drop trigger if exists diag_ecu_profiles_guard_status on automind.diag_ecu_profiles;
create trigger diag_ecu_profiles_guard_status before insert or update on automind.diag_ecu_profiles
  for each row execute function automind.guard_diag_profile_status();

-- -----------------------------------------------------------------------------
-- Grants & RLS
-- -----------------------------------------------------------------------------
alter table automind.diag_controller_catalog enable row level security;
alter table automind.diag_ecu_profiles enable row level security;

-- Catalogue is reference data: readable by everyone (automind_app), written by
-- migrations/owner only (no client writes).
grant select on automind.diag_controller_catalog to automind_app;
revoke insert, update, delete on automind.diag_controller_catalog from automind_app;
grant select, insert, update, delete on automind.diag_ecu_profiles to automind_app;

drop policy if exists diag_controller_catalog_read on automind.diag_controller_catalog;
create policy diag_controller_catalog_read on automind.diag_controller_catalog
  for select to automind_app using (true);

-- Profiles: approved rows are visible to everyone; everything else (unverified,
-- demo_only, rejected) is visible to platform admins only. Submit/approve/update
-- is restricted to platform admins.
drop policy if exists diag_profiles_select on automind.diag_ecu_profiles;
create policy diag_profiles_select on automind.diag_ecu_profiles for select to automind_app
  using (verification_status in ('verified_vehicle_trace', 'licensed_oem', 'standard_specification')
         or automind.is_platform_admin());
drop policy if exists diag_profiles_insert on automind.diag_ecu_profiles;
create policy diag_profiles_insert on automind.diag_ecu_profiles for insert to automind_app
  with check (automind.is_platform_admin());
drop policy if exists diag_profiles_update on automind.diag_ecu_profiles;
create policy diag_profiles_update on automind.diag_ecu_profiles for update to automind_app
  using (automind.is_platform_admin()) with check (automind.is_platform_admin());
