-- =============================================================================
-- AutoMind AI — core schema (migration 1/4)
--
-- Everything lives in the dedicated `automind` schema so the platform never
-- collides with other applications in the same Postgres database.
--
-- Conventions
--   * uuid primary keys (gen_random_uuid), timestamptz everywhere.
--   * Enumerations are text + CHECK constraints (cheap to evolve).
--   * Sensitive identifiers (VIN, plate number, MFA secret) are encrypted in
--     the application layer (AES-256-GCM, key outside the database). The DB
--     stores ciphertext plus an HMAC "blind index" for exact-match lookups.
--   * `data_mode` on every diagnostic artefact separates real vehicle data
--     (live) from simulated (demo) and re-played (replay) data.
-- =============================================================================

create schema if not exists automind;
comment on schema automind is 'AutoMind AI — vehicle diagnostics platform';

-- gen_random_uuid() is core since PG13; pgcrypto is only used for digest().
create schema if not exists extensions;
create extension if not exists pgcrypto with schema extensions;

-- -----------------------------------------------------------------------------
-- Generic helpers
-- -----------------------------------------------------------------------------
create or replace function automind.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- Identity & tenancy
-- -----------------------------------------------------------------------------
create table automind.users (
  id                    uuid primary key default gen_random_uuid(),
  email                 text not null,
  password_hash         text not null,                -- Argon2id (PHC string)
  full_name             text,
  phone                 text,
  locale                text not null default 'ar' check (locale in ('ar', 'en')),
  platform_role         text not null default 'user'
                        check (platform_role in ('user', 'support', 'admin', 'super_admin')),
  status                text not null default 'active'
                        check (status in ('active', 'suspended', 'pending_deletion', 'deleted')),
  mfa_enabled           boolean not null default false,
  mfa_secret_ciphertext bytea,                        -- TOTP secret, app-layer encrypted
  email_verified_at     timestamptz,
  failed_login_count    integer not null default 0 check (failed_login_count >= 0),
  locked_until          timestamptz,
  last_login_at         timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  deleted_at            timestamptz,
  constraint users_email_format check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  constraint users_admin_requires_mfa_secret
    check (not mfa_enabled or mfa_secret_ciphertext is not null)
);
create unique index users_email_lower_uq on automind.users (lower(email)) where deleted_at is null;
comment on column automind.users.password_hash is 'Argon2id hash; never a reversible value';

create table automind.auth_sessions (
  id                  uuid primary key default gen_random_uuid(),
  user_id             uuid not null references automind.users(id) on delete cascade,
  refresh_token_hash  bytea not null,                 -- SHA-256 of the opaque refresh token
  family_id           uuid not null,                  -- rotation family (reuse detection)
  user_agent          text,
  ip_address          inet,
  mfa_verified        boolean not null default false,
  created_at          timestamptz not null default now(),
  expires_at          timestamptz not null,
  rotated_at          timestamptz,
  revoked_at          timestamptz,
  constraint auth_sessions_expiry check (expires_at > created_at)
);
create unique index auth_sessions_token_uq on automind.auth_sessions (refresh_token_hash);
create index auth_sessions_user_idx on automind.auth_sessions (user_id) where revoked_at is null;
create index auth_sessions_family_idx on automind.auth_sessions (family_id);

create table automind.organizations (
  id            uuid primary key default gen_random_uuid(),
  name          text not null check (length(trim(name)) > 0),
  kind          text not null check (kind in ('workshop', 'fleet', 'supplier', 'platform')),
  cr_number     text,                                 -- Saudi commercial registration
  vat_number    text,
  country_code  char(2) not null default 'SA',
  city          text,
  status        text not null default 'active' check (status in ('pending', 'active', 'suspended', 'closed')),
  created_by    uuid references automind.users(id) on delete set null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create unique index organizations_cr_uq on automind.organizations (country_code, cr_number) where cr_number is not null;

create table automind.organization_members (
  organization_id uuid not null references automind.organizations(id) on delete cascade,
  user_id         uuid not null references automind.users(id) on delete cascade,
  role            text not null check (role in ('owner', 'admin', 'technician', 'advisor', 'viewer')),
  status          text not null default 'active' check (status in ('invited', 'active', 'disabled')),
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  primary key (organization_id, user_id)
);
create index organization_members_user_idx on automind.organization_members (user_id);

create table automind.user_consents (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references automind.users(id) on delete cascade,
  purpose          text not null check (purpose in (
                     'terms', 'privacy_policy', 'diagnostic_processing',
                     'ai_processing', 'training_use', 'marketing', 'share_with_workshop')),
  document_version text not null,
  granted          boolean not null,
  ip_address       inet,
  created_at       timestamptz not null default now()
);
create index user_consents_user_purpose_idx on automind.user_consents (user_id, purpose, created_at desc);

create table automind.data_requests (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references automind.users(id) on delete cascade,
  kind         text not null check (kind in ('export', 'delete')),
  status       text not null default 'pending' check (status in ('pending', 'processing', 'completed', 'rejected')),
  result_path  text,                                  -- storage path of export archive
  requested_at timestamptz not null default now(),
  completed_at timestamptz,
  notes        text
);
create index data_requests_user_idx on automind.data_requests (user_id, requested_at desc);

-- -----------------------------------------------------------------------------
-- Manufacturer packs (needed before vehicles/procedures reference them)
-- -----------------------------------------------------------------------------
create table automind.manufacturer_packs (
  id                   uuid primary key default gen_random_uuid(),
  key                  text not null check (key ~ '^[a-z0-9][a-z0-9_.-]*$'),
  name                 text not null,
  version              text not null check (version ~ '^\d+\.\d+\.\d+$'),
  data_class           text not null check (data_class in ('standard_obd2', 'manufacturer_specific')),
  makes                text[] not null default '{}',
  models               jsonb not null default '[]'::jsonb,
  year_from            smallint check (year_from between 1980 and 2100),
  year_to              smallint check (year_to between 1980 and 2100),
  supported_ecus       jsonb not null default '[]'::jsonb,
  extended_pids        jsonb not null default '[]'::jsonb,
  services             jsonb not null default '[]'::jsonb,
  supported_devices    jsonb not null default '[]'::jsonb,
  safety_requirements  jsonb not null default '{}'::jsonb,
  license_source       text not null,                  -- e.g. 'SAE J1979 (public)', OEM agreement id
  license_expires_at   date,
  status               text not null default 'draft' check (status in ('draft', 'testing', 'published', 'retired')),
  checksum_sha256      text,
  published_at         timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint manufacturer_packs_key_version_uq unique (key, version),
  constraint manufacturer_packs_years check (year_from is null or year_to is null or year_from <= year_to),
  constraint manufacturer_packs_published_has_checksum
    check (status <> 'published' or (checksum_sha256 is not null and published_at is not null))
);

-- -----------------------------------------------------------------------------
-- Vehicles & devices
-- -----------------------------------------------------------------------------
create table automind.vehicles (
  id                  uuid primary key default gen_random_uuid(),
  owner_user_id       uuid references automind.users(id) on delete cascade,
  organization_id     uuid references automind.organizations(id) on delete cascade,
  vin_ciphertext      bytea,                          -- AES-256-GCM(VIN)
  vin_blind_index     bytea,                          -- HMAC-SHA256(VIN) for lookup
  vin_wmi             char(3),                        -- manufacturer identifier (non-personal)
  vin_model_year_code char(1),
  make                text,
  model               text,
  model_year          smallint check (model_year between 1980 and 2100),
  engine              text,
  fuel_type           text check (fuel_type in ('gasoline', 'diesel', 'hybrid', 'electric', 'flex', 'lpg', 'cng', 'other')),
  transmission        text check (transmission in ('automatic', 'manual', 'cvt', 'dct', 'other')),
  nickname            text,
  plate_ciphertext    bytea,
  odometer_km         integer check (odometer_km >= 0),
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  deleted_at          timestamptz,
  constraint vehicles_has_owner check (owner_user_id is not null or organization_id is not null),
  constraint vehicles_vin_pair check ((vin_ciphertext is null) = (vin_blind_index is null))
);
create index vehicles_owner_idx on automind.vehicles (owner_user_id) where deleted_at is null;
create index vehicles_org_idx on automind.vehicles (organization_id) where deleted_at is null;
create unique index vehicles_owner_vin_uq on automind.vehicles (owner_user_id, vin_blind_index)
  where vin_blind_index is not null and deleted_at is null and owner_user_id is not null;
create unique index vehicles_org_vin_uq on automind.vehicles (organization_id, vin_blind_index)
  where vin_blind_index is not null and deleted_at is null and organization_id is not null;

create table automind.vehicle_profiles (
  vehicle_id            uuid primary key references automind.vehicles(id) on delete cascade,
  obd_protocol_code     text,                         -- ELM327 ATDPN code, e.g. '6'
  obd_protocol_name     text,                         -- e.g. 'ISO 15765-4 (CAN 11/500)'
  obd_standard          text,                         -- PID 0x1C decoded
  ecus                  jsonb not null default '[]'::jsonb,   -- [{address:'7E8', name:'ECM', ...}]
  supported_pids        jsonb not null default '{}'::jsonb,   -- {"01": ["0C","0D",...], "09": [...]}
  calibration_ids       jsonb not null default '[]'::jsonb,
  readiness_monitors    jsonb not null default '{}'::jsonb,
  manufacturer_pack_id  uuid references automind.manufacturer_packs(id) on delete set null,
  last_scanned_at       timestamptz,
  updated_at            timestamptz not null default now()
);

create table automind.obd_devices (
  id                uuid primary key default gen_random_uuid(),
  owner_user_id     uuid references automind.users(id) on delete cascade,
  organization_id   uuid references automind.organizations(id) on delete cascade,
  name              text not null,
  adapter_type      text not null default 'elm327' check (adapter_type in ('elm327', 'stn11xx', 'stn21xx', 'j2534', 'other')),
  transport         text not null check (transport in ('wifi_tcp', 'ble', 'usb_serial', 'bt_classic')),
  host              text,
  port              integer check (port between 1 and 65535),
  ble_device_id     text,
  ble_service_uuid  text,
  ble_notify_uuid   text,
  ble_write_uuid    text,
  firmware_version  text,                             -- ATI response, e.g. 'ELM327 v1.5'
  device_description text,                            -- AT@1 response
  is_certified      boolean not null default false,   -- approved for advanced (level 2+) functions
  settings          jsonb not null default '{}'::jsonb,
  last_seen_at      timestamptz,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now(),
  constraint obd_devices_has_owner check (owner_user_id is not null or organization_id is not null),
  constraint obd_devices_tcp_target check (transport <> 'wifi_tcp' or (host is not null and port is not null))
);
create index obd_devices_owner_idx on automind.obd_devices (owner_user_id);
create index obd_devices_org_idx on automind.obd_devices (organization_id);

create table automind.vehicle_connections (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references automind.users(id) on delete cascade,
  vehicle_id        uuid references automind.vehicles(id) on delete set null,
  device_id         uuid references automind.obd_devices(id) on delete set null,
  data_mode         text not null check (data_mode in ('live', 'demo', 'replay')),
  transport         text check (transport in ('wifi_tcp', 'ble', 'usb_serial', 'bt_classic', 'in_process')),
  adapter_status    text not null check (adapter_status in ('connected', 'unreachable', 'timeout', 'rejected', 'error')),
  ecu_status        text not null check (ecu_status in ('connected', 'no_response', 'bus_error', 'not_attempted', 'error')),
  protocol_code     text,
  protocol_name     text,
  adapter_firmware  text,
  attempts          smallint not null default 1 check (attempts >= 1),
  latency_ms        integer check (latency_ms >= 0),
  error_code        text,
  error_message     text,
  app_platform      text,
  app_version       text,
  started_at        timestamptz not null default now(),
  ended_at          timestamptz,
  constraint vehicle_connections_time check (ended_at is null or ended_at >= started_at)
);
create index vehicle_connections_user_idx on automind.vehicle_connections (user_id, started_at desc);
create index vehicle_connections_started_brin on automind.vehicle_connections using brin (started_at);

-- -----------------------------------------------------------------------------
-- Diagnostics
-- -----------------------------------------------------------------------------
create table automind.diagnostic_sessions (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid not null references automind.users(id) on delete cascade,
  organization_id      uuid references automind.organizations(id) on delete set null,
  vehicle_id           uuid references automind.vehicles(id) on delete set null,
  device_id            uuid references automind.obd_devices(id) on delete set null,
  connection_id        uuid references automind.vehicle_connections(id) on delete set null,
  data_mode            text not null check (data_mode in ('live', 'demo', 'replay')),
  demo_scenario_key    text,
  source_recording_id  uuid,                           -- FK added after telemetry_recordings
  status               text not null default 'in_progress'
                       check (status in ('in_progress', 'completed', 'failed', 'cancelled')),
  protocol_name        text,
  mil_on               boolean,
  dtc_count            smallint not null default 0 check (dtc_count >= 0),
  health_score         smallint check (health_score between 0 and 100),
  odometer_km          integer check (odometer_km >= 0),
  summary              jsonb not null default '{}'::jsonb,
  engine_version       text,                           -- diagnosis engine version
  kb_version           text,                           -- knowledge base version
  app_platform         text,
  app_version          text,
  started_at           timestamptz not null default now(),
  completed_at         timestamptz,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  constraint diagnostic_sessions_demo_has_scenario check (data_mode <> 'demo' or demo_scenario_key is not null),
  constraint diagnostic_sessions_replay_has_source check (data_mode <> 'replay' or source_recording_id is not null),
  constraint diagnostic_sessions_time check (completed_at is null or completed_at >= started_at)
);
create index diagnostic_sessions_user_idx on automind.diagnostic_sessions (user_id, started_at desc);
create index diagnostic_sessions_vehicle_idx on automind.diagnostic_sessions (vehicle_id, started_at desc);
create index diagnostic_sessions_org_idx on automind.diagnostic_sessions (organization_id, started_at desc) where organization_id is not null;
create index diagnostic_sessions_started_brin on automind.diagnostic_sessions using brin (started_at);

create table automind.dtc_definitions (
  id                    uuid primary key default gen_random_uuid(),
  code                  text not null check (code ~ '^[PCBU][0-9A-F]{4}$'),
  manufacturer_pack_id  uuid references automind.manufacturer_packs(id) on delete cascade,
  is_generic            boolean not null,
  system                text not null check (system in ('powertrain', 'chassis', 'body', 'network')),
  subsystem             text,
  description_en        text not null,
  description_ar        text not null,
  default_severity      text not null default 'medium' check (default_severity in ('info', 'low', 'medium', 'high', 'critical')),
  source                text not null,                -- e.g. 'SAE J2012 (public descriptions)'
  kb_version            text not null,
  updated_at            timestamptz not null default now(),
  constraint dtc_definitions_code_pack_uq unique nulls not distinct (code, manufacturer_pack_id)
);

create table automind.diagnostic_trouble_codes (
  id                 uuid primary key default gen_random_uuid(),
  session_id         uuid not null references automind.diagnostic_sessions(id) on delete cascade,
  vehicle_id         uuid references automind.vehicles(id) on delete set null,
  code               text not null check (code ~ '^[PCBU][0-9A-F]{4}$'),
  status             text not null check (status in ('stored', 'pending', 'permanent')),
  source_service     text not null check (source_service in ('03', '07', '0A', '19')),  -- 19 = UDS (future)
  ecu_address        text,                             -- e.g. '7E8'
  ecu_name           text,
  description_en     text,
  description_ar     text,
  is_generic         boolean,
  freeze_frame       jsonb,
  detected_at        timestamptz not null default now(),
  constraint diagnostic_trouble_codes_uq unique (session_id, code, status, ecu_address)
);
create index diagnostic_trouble_codes_code_idx on automind.diagnostic_trouble_codes (code);
create index diagnostic_trouble_codes_vehicle_idx on automind.diagnostic_trouble_codes (vehicle_id, detected_at desc);

-- Raw telemetry: range-partitioned by time (monthly) — see migration 3.
create table automind.telemetry_readings (
  session_id  uuid not null references automind.diagnostic_sessions(id) on delete cascade,
  ts          timestamptz not null,
  pid         text not null check (pid ~ '^[0-9A-F]{4,6}$'),   -- service+pid, e.g. '010C'
  signal      text not null,                                  -- decoded output key, e.g. 'engine_rpm'
  value       double precision,
  unit        text,
  ecu_address text,
  primary key (session_id, signal, ts)
) partition by range (ts);
comment on table automind.telemetry_readings is
  'Hot store for decoded samples. Monthly partitions, dropped after the retention window; full sessions are archived as compressed recordings in object storage.';

create table automind.telemetry_aggregates (
  session_id   uuid not null references automind.diagnostic_sessions(id) on delete cascade,
  signal       text not null,
  pid          text not null,
  unit         text,
  sample_count integer not null check (sample_count >= 0),
  min_value    double precision,
  max_value    double precision,
  avg_value    double precision,
  stddev_value double precision,
  first_ts     timestamptz,
  last_ts      timestamptz,
  primary key (session_id, signal)
);

create table automind.telemetry_recordings (
  id                   uuid primary key default gen_random_uuid(),
  session_id           uuid references automind.diagnostic_sessions(id) on delete set null,
  user_id              uuid not null references automind.users(id) on delete cascade,
  vehicle_id           uuid references automind.vehicles(id) on delete set null,
  data_mode            text not null check (data_mode in ('live', 'demo', 'replay')),
  format               text not null default 'automind.recording.v1',
  duration_ms          integer not null check (duration_ms >= 0),
  sample_count         integer not null check (sample_count >= 0),
  signals              text[] not null default '{}',
  storage_bucket       text,
  storage_path         text,
  inline_payload       jsonb,                         -- small recordings (<1 MB) may be stored inline
  size_bytes           bigint check (size_bytes >= 0),
  sha256               text,
  consent_for_training boolean not null default false,
  created_at           timestamptz not null default now(),
  expires_at           timestamptz,
  constraint telemetry_recordings_has_payload check (storage_path is not null or inline_payload is not null)
);
create index telemetry_recordings_user_idx on automind.telemetry_recordings (user_id, created_at desc);
create index telemetry_recordings_session_idx on automind.telemetry_recordings (session_id);

alter table automind.diagnostic_sessions
  add constraint diagnostic_sessions_source_recording_fk
  foreign key (source_recording_id) references automind.telemetry_recordings(id) on delete set null;

create table automind.diagnostic_findings (
  id             uuid primary key default gen_random_uuid(),
  session_id     uuid not null references automind.diagnostic_sessions(id) on delete cascade,
  rule_id        text not null,
  rule_version   text not null,
  system         text not null check (system in (
                   'engine', 'fuel', 'ignition', 'air_intake', 'cooling', 'charging',
                   'emissions', 'transmission', 'ac', 'electrical', 'network', 'other')),
  title_en       text not null,
  title_ar       text not null,
  severity       text not null check (severity in ('info', 'low', 'medium', 'high', 'critical')),
  status         text not null default 'suspected' check (status in ('suspected', 'likely', 'confirmed', 'ruled_out', 'inconclusive')),
  confidence     numeric(4,3) not null check (confidence between 0 and 1),
  related_dtcs   text[] not null default '{}',
  details        jsonb not null default '{}'::jsonb,
  created_at     timestamptz not null default now()
);
create index diagnostic_findings_session_idx on automind.diagnostic_findings (session_id);
create index diagnostic_findings_rule_idx on automind.diagnostic_findings (rule_id);

create table automind.ai_diagnoses (
  id                   uuid primary key default gen_random_uuid(),
  session_id           uuid not null references automind.diagnostic_sessions(id) on delete cascade,
  finding_id           uuid references automind.diagnostic_findings(id) on delete cascade,
  engine               text not null check (engine in ('rules', 'llm', 'hybrid')),
  engine_version       text not null,
  model                text,                          -- LLM model id when engine uses one
  prompt_version       text,
  language             text not null check (language in ('ar', 'en')),
  input_sha256         text not null,                 -- reproducibility
  summary_owner        text not null,
  summary_technician   text not null,
  probable_causes      jsonb not null default '[]'::jsonb,
  recommended_tests    jsonb not null default '[]'::jsonb,
  repair_actions       jsonb not null default '[]'::jsonb,
  parts_candidates     jsonb not null default '[]'::jsonb,
  missing_data         jsonb not null default '[]'::jsonb,
  overall_confidence   numeric(4,3) check (overall_confidence between 0 and 1),
  input_tokens         integer check (input_tokens >= 0),
  output_tokens        integer check (output_tokens >= 0),
  cost_usd             numeric(10,6) check (cost_usd >= 0),
  latency_ms           integer check (latency_ms >= 0),
  status               text not null default 'completed' check (status in ('completed', 'failed', 'fallback')),
  error_message        text,
  user_feedback        text check (user_feedback in ('helpful', 'not_helpful')),
  confirmed_cause      text,                          -- filled after repair (learning signal)
  created_at           timestamptz not null default now()
);
create index ai_diagnoses_session_idx on automind.ai_diagnoses (session_id, created_at desc);
create index ai_diagnoses_created_brin on automind.ai_diagnoses using brin (created_at);

create table automind.diagnosis_evidence (
  id              uuid primary key default gen_random_uuid(),
  session_id      uuid not null references automind.diagnostic_sessions(id) on delete cascade,
  finding_id      uuid references automind.diagnostic_findings(id) on delete cascade,
  diagnosis_id    uuid references automind.ai_diagnoses(id) on delete cascade,
  kind            text not null check (kind in (
                    'dtc', 'pid_reading', 'pid_statistic', 'freeze_frame',
                    'user_measurement', 'technician_note', 'kb_reference', 'missing_data')),
  is_measured     boolean not null,                   -- true = observed data, false = inference/reference
  signal          text,
  observed_value  double precision,
  observed_text   text,
  unit            text,
  expected_min    double precision,
  expected_max    double precision,
  expected_context text,                              -- e.g. 'warm idle, 650-900 rpm'
  assessment      text not null check (assessment in ('normal', 'abnormal', 'inconclusive', 'supports', 'contradicts')),
  weight          numeric(4,3) not null default 0.5 check (weight between 0 and 1),
  note_en         text,
  note_ar         text,
  created_at      timestamptz not null default now(),
  constraint diagnosis_evidence_parent check (finding_id is not null or diagnosis_id is not null)
);
create index diagnosis_evidence_session_idx on automind.diagnosis_evidence (session_id);
create index diagnosis_evidence_finding_idx on automind.diagnosis_evidence (finding_id);

-- -----------------------------------------------------------------------------
-- AutoMind Control (service functions) — dangerous functions disabled by default
-- -----------------------------------------------------------------------------
create table automind.service_procedures (
  id                    uuid primary key default gen_random_uuid(),
  key                   text not null unique check (key ~ '^[a-z0-9_]+$'),
  level                 smallint not null check (level between 1 and 4),
  name_en               text not null,
  name_ar               text not null,
  description_en        text,
  description_ar        text,
  risk_level            text not null check (risk_level in ('low', 'medium', 'high', 'prohibited')),
  safety_category       text not null check (safety_category in (
                          'general', 'emissions', 'brakes', 'steering', 'airbag',
                          'immobilizer', 'odometer', 'powertrain', 'body')),
  required_engine_state text not null default 'any' check (required_engine_state in ('off', 'ignition_on', 'running', 'any')),
  preconditions         jsonb not null default '[]'::jsonb,
  obd_service           text,                          -- e.g. '04' for clear DTCs
  manufacturer_pack_id  uuid references automind.manufacturer_packs(id) on delete cascade,
  enabled_by_default    boolean not null default false,
  is_prohibited         boolean not null default false,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz not null default now(),
  -- Safety-critical systems are never enabled by default.
  constraint service_procedures_safety_default check (
    not enabled_by_default
    or (safety_category not in ('brakes', 'steering', 'airbag', 'immobilizer', 'odometer') and risk_level in ('low', 'medium'))),
  -- Prohibited operations (odometer change, emissions delete, immobilizer bypass) can never be enabled.
  constraint service_procedures_prohibited check (not is_prohibited or (risk_level = 'prohibited' and not enabled_by_default)),
  constraint service_procedures_odometer_prohibited check (safety_category <> 'odometer' or is_prohibited)
);

create table automind.procedure_allowlist (
  id                   uuid primary key default gen_random_uuid(),
  procedure_id         uuid not null references automind.service_procedures(id) on delete cascade,
  manufacturer_pack_id uuid references automind.manufacturer_packs(id) on delete cascade,
  make                 text,
  model                text,
  year_from            smallint,
  year_to              smallint,
  ecu_address          text,
  adapter_type         text,
  requires_certified_device boolean not null default true,
  approved_by          uuid references automind.users(id) on delete set null,
  approved_at          timestamptz,
  validation_notes     text,
  active               boolean not null default false,
  created_at           timestamptz not null default now(),
  constraint procedure_allowlist_years check (year_from is null or year_to is null or year_from <= year_to),
  constraint procedure_allowlist_active_requires_approval check (not active or (approved_by is not null and approved_at is not null))
);
create index procedure_allowlist_proc_idx on automind.procedure_allowlist (procedure_id) where active;

create table automind.control_operations (
  id                uuid primary key default gen_random_uuid(),
  user_id           uuid not null references automind.users(id) on delete cascade,
  vehicle_id        uuid references automind.vehicles(id) on delete set null,
  session_id        uuid references automind.diagnostic_sessions(id) on delete set null,
  device_id         uuid references automind.obd_devices(id) on delete set null,
  procedure_id      uuid not null references automind.service_procedures(id),
  data_mode         text not null check (data_mode in ('live', 'demo', 'replay')),
  consent_text      text not null,
  consented_at      timestamptz not null,
  status            text not null check (status in ('requested', 'rejected_policy', 'executing', 'succeeded', 'failed')),
  rejection_reason  text,
  request_frames    text[],                           -- raw commands sent (hex/AT)
  response_frames   text[],
  result            jsonb not null default '{}'::jsonb,
  created_at        timestamptz not null default now(),
  finished_at       timestamptz
);
create index control_operations_user_idx on automind.control_operations (user_id, created_at desc);

-- -----------------------------------------------------------------------------
-- Maintenance history
-- -----------------------------------------------------------------------------
create table automind.maintenance_records (
  id               uuid primary key default gen_random_uuid(),
  vehicle_id       uuid not null references automind.vehicles(id) on delete cascade,
  created_by       uuid references automind.users(id) on delete set null,
  organization_id  uuid references automind.organizations(id) on delete set null,
  session_id       uuid references automind.diagnostic_sessions(id) on delete set null,
  service_date     date not null,
  odometer_km      integer check (odometer_km >= 0),
  category         text not null check (category in (
                     'oil_change', 'filters', 'brakes', 'tires', 'battery', 'cooling', 'ac',
                     'transmission', 'engine_repair', 'electrical', 'inspection', 'other')),
  description      text not null,
  cost_amount      numeric(12,2) check (cost_amount >= 0),
  currency         char(3) not null default 'SAR',
  parts            jsonb not null default '[]'::jsonb,
  source           text not null default 'owner' check (source in ('owner', 'workshop', 'imported')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index maintenance_records_vehicle_idx on automind.maintenance_records (vehicle_id, service_date desc);

-- -----------------------------------------------------------------------------
-- AutoMind Garage
-- -----------------------------------------------------------------------------
create table automind.workshops (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null unique references automind.organizations(id) on delete cascade,
  name_ar          text not null,
  name_en          text,
  city             text not null,
  district         text,
  address          text,
  latitude         numeric(9,6) check (latitude between -90 and 90),
  longitude        numeric(9,6) check (longitude between -180 and 180),
  phone            text,
  services         text[] not null default '{}',
  makes_supported  text[] not null default '{}',
  working_hours    jsonb not null default '{}'::jsonb,
  rating_avg       numeric(3,2) check (rating_avg between 0 and 5),
  rating_count     integer not null default 0 check (rating_count >= 0),
  verified_at      timestamptz,
  status           text not null default 'pending' check (status in ('pending', 'active', 'suspended')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index workshops_city_idx on automind.workshops (city) where status = 'active';

create table automind.report_shares (
  id                  uuid primary key default gen_random_uuid(),
  session_id          uuid not null references automind.diagnostic_sessions(id) on delete cascade,
  owner_user_id       uuid not null references automind.users(id) on delete cascade,
  shared_with_org_id  uuid not null references automind.organizations(id) on delete cascade,
  include_vin         boolean not null default false,
  include_live_data   boolean not null default true,
  consent_version     text not null,
  granted_at          timestamptz not null default now(),
  expires_at          timestamptz not null default (now() + interval '30 days'),
  revoked_at          timestamptz,
  constraint report_shares_expiry check (expires_at > granted_at)
);
create index report_shares_org_idx on automind.report_shares (shared_with_org_id) where revoked_at is null;
create index report_shares_session_idx on automind.report_shares (session_id);

create table automind.workshop_bookings (
  id               uuid primary key default gen_random_uuid(),
  workshop_id      uuid not null references automind.workshops(id) on delete cascade,
  customer_user_id uuid not null references automind.users(id) on delete cascade,
  vehicle_id       uuid references automind.vehicles(id) on delete set null,
  report_share_id  uuid references automind.report_shares(id) on delete set null,
  scheduled_at     timestamptz not null,
  status           text not null default 'requested' check (status in (
                     'requested', 'confirmed', 'in_progress', 'awaiting_parts', 'completed', 'cancelled', 'no_show')),
  customer_notes   text,
  workshop_notes   text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
create index workshop_bookings_workshop_idx on automind.workshop_bookings (workshop_id, scheduled_at);
create index workshop_bookings_customer_idx on automind.workshop_bookings (customer_user_id, scheduled_at desc);

create table automind.repair_quotes (
  id               uuid primary key default gen_random_uuid(),
  booking_id       uuid references automind.workshop_bookings(id) on delete set null,
  workshop_id      uuid not null references automind.workshops(id) on delete cascade,
  customer_user_id uuid not null references automind.users(id) on delete cascade,
  vehicle_id       uuid references automind.vehicles(id) on delete set null,
  session_id       uuid references automind.diagnostic_sessions(id) on delete set null,
  status           text not null default 'draft' check (status in ('draft', 'sent', 'accepted', 'rejected', 'expired', 'withdrawn')),
  items            jsonb not null default '[]'::jsonb,   -- [{type:'labor'|'part', description, qty, unit_price}]
  subtotal         numeric(12,2) not null default 0 check (subtotal >= 0),
  vat_rate         numeric(5,4) not null default 0.15 check (vat_rate between 0 and 1),
  vat_amount       numeric(12,2) not null default 0 check (vat_amount >= 0),
  total            numeric(12,2) not null default 0 check (total >= 0),
  currency         char(3) not null default 'SAR',
  valid_until      date,
  created_by       uuid references automind.users(id) on delete set null,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now(),
  constraint repair_quotes_total check (total = subtotal + vat_amount)
);
create index repair_quotes_workshop_idx on automind.repair_quotes (workshop_id, created_at desc);
create index repair_quotes_customer_idx on automind.repair_quotes (customer_user_id, created_at desc);

create table automind.workshop_reviews (
  id          uuid primary key default gen_random_uuid(),
  booking_id  uuid not null unique references automind.workshop_bookings(id) on delete cascade,
  workshop_id uuid not null references automind.workshops(id) on delete cascade,
  user_id     uuid not null references automind.users(id) on delete cascade,
  rating      smallint not null check (rating between 1 and 5),
  comment     text,
  created_at  timestamptz not null default now()
);
create index workshop_reviews_workshop_idx on automind.workshop_reviews (workshop_id);

-- -----------------------------------------------------------------------------
-- AutoMind Parts
-- -----------------------------------------------------------------------------
create table automind.parts (
  id                  uuid primary key default gen_random_uuid(),
  part_number         text not null,
  brand               text not null,
  part_type           text not null check (part_type in ('oem', 'oes', 'aftermarket', 'remanufactured', 'used')),
  name_en             text not null,
  name_ar             text,
  category            text not null,
  description         text,
  specs               jsonb not null default '{}'::jsonb,
  interchange_numbers text[] not null default '{}',
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  constraint parts_brand_number_uq unique (brand, part_number)
);
create index parts_interchange_gin on automind.parts using gin (interchange_numbers);

create table automind.vehicle_part_fitments (
  id           uuid primary key default gen_random_uuid(),
  part_id      uuid not null references automind.parts(id) on delete cascade,
  make         text not null,
  model        text not null,
  year_from    smallint not null,
  year_to      smallint not null,
  engine_code  text,
  vin_pattern  text,                                  -- optional VDS/VIS regex from licensed catalogue
  position     text,
  source       text not null,                         -- catalogue licence / provider
  notes        text,
  created_at   timestamptz not null default now(),
  constraint vehicle_part_fitments_years check (year_from <= year_to)
);
create index vehicle_part_fitments_lookup_idx on automind.vehicle_part_fitments (lower(make), lower(model), year_from, year_to);
create index vehicle_part_fitments_part_idx on automind.vehicle_part_fitments (part_id);

create table automind.suppliers (
  id               uuid primary key default gen_random_uuid(),
  organization_id  uuid not null unique references automind.organizations(id) on delete cascade,
  name             text not null,
  city             text,
  delivery_regions text[] not null default '{}',
  rating_avg       numeric(3,2) check (rating_avg between 0 and 5),
  status           text not null default 'pending' check (status in ('pending', 'active', 'suspended')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);

create table automind.supplier_inventory (
  id             uuid primary key default gen_random_uuid(),
  supplier_id    uuid not null references automind.suppliers(id) on delete cascade,
  part_id        uuid not null references automind.parts(id) on delete cascade,
  sku            text,
  condition      text not null default 'new' check (condition in ('new', 'used', 'refurbished')),
  price          numeric(12,2) not null check (price >= 0),
  currency       char(3) not null default 'SAR',
  quantity       integer not null default 0 check (quantity >= 0),
  lead_time_days smallint check (lead_time_days >= 0),
  updated_at     timestamptz not null default now(),
  constraint supplier_inventory_uq unique (supplier_id, part_id, condition)
);
create index supplier_inventory_part_idx on automind.supplier_inventory (part_id) where quantity > 0;

create table automind.parts_orders (
  id                       uuid primary key default gen_random_uuid(),
  user_id                  uuid not null references automind.users(id) on delete cascade,
  supplier_id              uuid not null references automind.suppliers(id),
  vehicle_id               uuid references automind.vehicles(id) on delete set null,
  session_id               uuid references automind.diagnostic_sessions(id) on delete set null,
  install_workshop_id      uuid references automind.workshops(id) on delete set null,
  -- A part is never ordered on a mere probability without the user knowing it.
  diagnosis_confirmation   text not null check (diagnosis_confirmation in (
                             'confirmed_by_technician', 'confirmed_by_test', 'user_acknowledged_unconfirmed', 'not_diagnosis_related')),
  status                   text not null default 'pending' check (status in (
                             'pending', 'reserved', 'paid', 'shipped', 'delivered', 'cancelled', 'refunded')),
  subtotal                 numeric(12,2) not null default 0 check (subtotal >= 0),
  vat_amount               numeric(12,2) not null default 0 check (vat_amount >= 0),
  total                    numeric(12,2) not null default 0 check (total >= 0),
  currency                 char(3) not null default 'SAR',
  created_at               timestamptz not null default now(),
  updated_at               timestamptz not null default now()
);
create index parts_orders_user_idx on automind.parts_orders (user_id, created_at desc);
create index parts_orders_supplier_idx on automind.parts_orders (supplier_id, created_at desc);

create table automind.parts_order_items (
  id                    uuid primary key default gen_random_uuid(),
  order_id              uuid not null references automind.parts_orders(id) on delete cascade,
  supplier_inventory_id uuid references automind.supplier_inventory(id) on delete set null,
  part_id               uuid not null references automind.parts(id),
  quantity              integer not null check (quantity > 0),
  unit_price            numeric(12,2) not null check (unit_price >= 0)
);
create index parts_order_items_order_idx on automind.parts_order_items (order_id);

-- -----------------------------------------------------------------------------
-- Commerce
-- -----------------------------------------------------------------------------
create table automind.subscription_plans (
  id                uuid primary key default gen_random_uuid(),
  key               text not null unique check (key ~ '^[a-z0-9_]+$'),
  name_en           text not null,
  name_ar           text not null,
  audience          text not null check (audience in ('individual', 'business')),
  price_monthly     numeric(10,2) check (price_monthly >= 0),
  price_yearly      numeric(10,2) check (price_yearly >= 0),
  currency          char(3) not null default 'SAR',
  features          jsonb not null default '{}'::jsonb,   -- feature flags
  limits            jsonb not null default '{}'::jsonb,   -- quotas
  store_product_ids jsonb not null default '{}'::jsonb,   -- {"app_store": "...", "google_play": "..."}
  active            boolean not null default true,
  sort_order        smallint not null default 0,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);

create table automind.subscriptions (
  id                        uuid primary key default gen_random_uuid(),
  user_id                   uuid references automind.users(id) on delete cascade,
  organization_id           uuid references automind.organizations(id) on delete cascade,
  plan_id                   uuid not null references automind.subscription_plans(id),
  status                    text not null check (status in ('trialing', 'active', 'past_due', 'cancelled', 'expired')),
  billing_period            text not null check (billing_period in ('monthly', 'yearly', 'lifetime', 'trial')),
  provider                  text not null check (provider in ('app_store', 'google_play', 'web_gateway', 'manual')),
  provider_subscription_id  text,
  current_period_start      timestamptz not null,
  current_period_end        timestamptz,
  cancel_at_period_end      boolean not null default false,
  cancelled_at              timestamptz,
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  constraint subscriptions_one_subject check ((user_id is null) <> (organization_id is null))
);
create unique index subscriptions_active_user_uq on automind.subscriptions (user_id)
  where status in ('trialing', 'active', 'past_due') and user_id is not null;
create unique index subscriptions_active_org_uq on automind.subscriptions (organization_id)
  where status in ('trialing', 'active', 'past_due') and organization_id is not null;
create unique index subscriptions_provider_uq on automind.subscriptions (provider, provider_subscription_id)
  where provider_subscription_id is not null;

create table automind.payments (
  id                   uuid primary key default gen_random_uuid(),
  user_id              uuid references automind.users(id) on delete set null,
  organization_id      uuid references automind.organizations(id) on delete set null,
  subscription_id      uuid references automind.subscriptions(id) on delete set null,
  parts_order_id       uuid references automind.parts_orders(id) on delete set null,
  booking_id           uuid references automind.workshop_bookings(id) on delete set null,
  amount               numeric(12,2) not null check (amount >= 0),
  currency             char(3) not null default 'SAR',
  provider             text not null check (provider in ('app_store', 'google_play', 'web_gateway', 'manual')),
  provider_payment_id  text,
  status               text not null check (status in ('pending', 'succeeded', 'failed', 'refunded', 'disputed')),
  paid_at              timestamptz,
  raw_payload          jsonb,
  created_at           timestamptz not null default now(),
  constraint payments_subject check (user_id is not null or organization_id is not null)
);
create unique index payments_provider_uq on automind.payments (provider, provider_payment_id) where provider_payment_id is not null;
create index payments_created_brin on automind.payments using brin (created_at);

create table automind.notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references automind.users(id) on delete cascade,
  kind        text not null,
  title       text not null,
  body        text,
  data        jsonb not null default '{}'::jsonb,
  channel     text not null default 'in_app' check (channel in ('in_app', 'push', 'email', 'sms')),
  sent_at     timestamptz,
  read_at     timestamptz,
  created_at  timestamptz not null default now()
);
create index notifications_user_unread_idx on automind.notifications (user_id, created_at desc) where read_at is null;

-- -----------------------------------------------------------------------------
-- Audit & operations
-- -----------------------------------------------------------------------------
create table automind.audit_logs (
  id             bigint generated always as identity primary key,
  occurred_at    timestamptz not null default now(),
  actor_user_id  uuid,                                -- no FK: audit survives user deletion
  actor_org_id   uuid,
  action         text not null,                        -- e.g. 'auth.login', 'control.clear_dtc'
  entity_type    text,
  entity_id      text,
  outcome        text not null default 'success' check (outcome in ('success', 'failure', 'denied')),
  ip_address     inet,
  user_agent     text,
  request_id     text,
  before_state   jsonb,
  after_state    jsonb,
  metadata       jsonb not null default '{}'::jsonb
);
create index audit_logs_occurred_brin on automind.audit_logs using brin (occurred_at);
create index audit_logs_actor_idx on automind.audit_logs (actor_user_id, occurred_at desc);
create index audit_logs_entity_idx on automind.audit_logs (entity_type, entity_id);

create or replace function automind.prevent_audit_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'audit_logs is append-only';
end;
$$;
create trigger audit_logs_no_update before update or delete on automind.audit_logs
  for each row execute function automind.prevent_audit_mutation();

create table automind.system_errors (
  id           bigint generated always as identity primary key,
  occurred_at  timestamptz not null default now(),
  component    text not null,                          -- 'api', 'obd', 'diagnosis', 'llm', ...
  error_code   text not null,
  message      text,
  request_id   text,
  user_id      uuid,
  context      jsonb not null default '{}'::jsonb
);
create index system_errors_occurred_brin on automind.system_errors using brin (occurred_at);
create index system_errors_component_idx on automind.system_errors (component, occurred_at desc);

-- -----------------------------------------------------------------------------
-- updated_at triggers
-- -----------------------------------------------------------------------------
do $$
declare
  t text;
begin
  foreach t in array array[
    'users', 'organizations', 'organization_members', 'manufacturer_packs', 'vehicles',
    'vehicle_profiles', 'obd_devices', 'diagnostic_sessions', 'service_procedures',
    'maintenance_records', 'workshops', 'workshop_bookings', 'repair_quotes', 'parts',
    'suppliers', 'parts_orders', 'subscription_plans', 'subscriptions'
  ] loop
    execute format(
      'create trigger %I before update on automind.%I for each row execute function automind.set_updated_at()',
      t || '_set_updated_at', t);
  end loop;
end;
$$;
