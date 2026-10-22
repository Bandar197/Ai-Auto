-- =============================================================================
-- AutoMind AI — tenant isolation with Row Level Security (migration 3/4)
--
-- Model
--   * The FastAPI backend is the only client of this schema. The schema is not
--     exposed through Supabase PostgREST, and anon/authenticated get nothing.
--   * For every user request the backend opens a transaction and runs:
--         select set_config('app.user_id', '<uuid>', true);
--         set local role automind_app;
--     `automind_app` is NOLOGIN and is subject to every policy below.
--   * System work (migrations, registration/login, workers) runs as the schema
--     owner, which bypasses RLS by design (ENABLE, not FORCE).
--   * Helper functions are SECURITY DEFINER so policies never recurse.
-- =============================================================================

do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'automind_app') then
    create role automind_app nologin noinherit;
  end if;
end;
$$;

-- Let the connecting backend role switch into automind_app (PG16+ needs SET option).
do $$
begin
  execute format('grant automind_app to %I with set true', current_user);
exception when others then
  -- older servers / superuser: plain membership is enough
  execute format('grant automind_app to %I', current_user);
end;
$$;

revoke all on schema automind from public;
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on schema automind from anon';
  end if;
  if exists (select 1 from pg_roles where rolname = 'authenticated') then
    execute 'revoke all on schema automind from authenticated';
  end if;
end;
$$;

grant usage on schema automind to automind_app;
grant usage on schema extensions to automind_app;
grant select, insert, update, delete on all tables in schema automind to automind_app;
grant usage, select on all sequences in schema automind to automind_app;
-- Secrets & sessions are system-only.
revoke all on automind.auth_sessions from automind_app;
revoke update, delete on automind.audit_logs from automind_app;
revoke all on automind.system_errors from automind_app;

-- -----------------------------------------------------------------------------
-- Context helpers
-- -----------------------------------------------------------------------------
create or replace function automind.current_user_id()
returns uuid
language sql
stable
set search_path = ''
as $$
  select nullif(current_setting('app.user_id', true), '')::uuid;
$$;

create or replace function automind.is_platform_admin()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from automind.users u
    where u.id = automind.current_user_id()
      and u.platform_role in ('admin', 'super_admin')
      and u.status = 'active');
$$;

create or replace function automind.is_platform_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from automind.users u
    where u.id = automind.current_user_id()
      and u.platform_role in ('support', 'admin', 'super_admin')
      and u.status = 'active');
$$;

create or replace function automind.is_org_member(p_org uuid, p_roles text[] default null)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from automind.organization_members m
    where m.organization_id = p_org
      and m.user_id = automind.current_user_id()
      and m.status = 'active'
      and (p_roles is null or m.role = any (p_roles)));
$$;

create or replace function automind.can_access_vehicle(p_vehicle uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from automind.vehicles v
    where v.id = p_vehicle
      and (v.owner_user_id = automind.current_user_id()
           or (v.organization_id is not null and automind.is_org_member(v.organization_id))))
    or automind.is_platform_staff();
$$;

create or replace function automind.can_write_vehicle(p_vehicle uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from automind.vehicles v
    where v.id = p_vehicle
      and (v.owner_user_id = automind.current_user_id()
           or (v.organization_id is not null
               and automind.is_org_member(v.organization_id, array['owner', 'admin', 'technician', 'advisor']))));
$$;

-- Read access to a diagnostic session: owner, members of the session's org,
-- members of an org the owner explicitly shared it with (active share), staff.
create or replace function automind.can_access_session(p_session uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from automind.diagnostic_sessions s
    where s.id = p_session
      and (s.user_id = automind.current_user_id()
           or (s.organization_id is not null and automind.is_org_member(s.organization_id))
           or exists (
             select 1 from automind.report_shares rs
             where rs.session_id = s.id
               and rs.revoked_at is null
               and rs.expires_at > now()
               and automind.is_org_member(rs.shared_with_org_id))))
    or automind.is_platform_staff();
$$;

create or replace function automind.can_write_session(p_session uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from automind.diagnostic_sessions s
    where s.id = p_session
      and (s.user_id = automind.current_user_id()
           or (s.organization_id is not null
               and automind.is_org_member(s.organization_id, array['owner', 'admin', 'technician']))));
$$;

create or replace function automind.workshop_org(p_workshop uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select organization_id from automind.workshops where id = p_workshop;
$$;

create or replace function automind.supplier_org(p_supplier uuid)
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select organization_id from automind.suppliers where id = p_supplier;
$$;

revoke all on function automind.is_platform_admin() from public;
revoke all on function automind.is_platform_staff() from public;
revoke all on function automind.is_org_member(uuid, text[]) from public;
revoke all on function automind.can_access_vehicle(uuid) from public;
revoke all on function automind.can_write_vehicle(uuid) from public;
revoke all on function automind.can_access_session(uuid) from public;
revoke all on function automind.can_write_session(uuid) from public;
revoke all on function automind.workshop_org(uuid) from public;
revoke all on function automind.supplier_org(uuid) from public;
grant execute on all functions in schema automind to automind_app;
-- Maintenance functions are for the owner/worker only.
revoke all on function automind.ensure_telemetry_partitions(int, int) from public, automind_app;
revoke all on function automind.drop_old_telemetry_partitions(int) from public, automind_app;

-- -----------------------------------------------------------------------------
-- Enable RLS on every table
-- -----------------------------------------------------------------------------
do $$
declare
  r record;
begin
  for r in
    select c.relname from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'automind' and c.relkind in ('r', 'p')
  loop
    execute format('alter table automind.%I enable row level security', r.relname);
  end loop;
end;
$$;

-- Shorthand used below: every policy targets automind_app only.

-- users ----------------------------------------------------------------------
create policy users_select on automind.users for select to automind_app
  using (id = automind.current_user_id() or automind.is_platform_staff());
create policy users_update on automind.users for update to automind_app
  using (id = automind.current_user_id() or automind.is_platform_admin())
  with check (id = automind.current_user_id() or automind.is_platform_admin());

-- Prevent privilege escalation: only admins may change platform_role/status.
create or replace function automind.guard_user_privileges()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user = 'automind_app' and not automind.is_platform_admin() then
    if new.platform_role is distinct from old.platform_role
       or new.status is distinct from old.status
       or new.password_hash is distinct from old.password_hash
       or new.failed_login_count is distinct from old.failed_login_count
       or new.locked_until is distinct from old.locked_until then
      raise exception 'not allowed to change protected user fields' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
create trigger users_guard_privileges before update on automind.users
  for each row execute function automind.guard_user_privileges();

-- organizations / members -----------------------------------------------------
create policy organizations_select on automind.organizations for select to automind_app
  using (automind.is_org_member(id) or automind.is_platform_staff()
         or (status = 'active' and kind in ('workshop', 'supplier')));   -- public directory
create policy organizations_update on automind.organizations for update to automind_app
  using (automind.is_org_member(id, array['owner', 'admin']) or automind.is_platform_admin())
  with check (automind.is_org_member(id, array['owner', 'admin']) or automind.is_platform_admin());
create policy organizations_insert on automind.organizations for insert to automind_app
  with check (created_by = automind.current_user_id());

create policy org_members_select on automind.organization_members for select to automind_app
  using (user_id = automind.current_user_id() or automind.is_org_member(organization_id) or automind.is_platform_staff());
create policy org_members_manage on automind.organization_members for all to automind_app
  using (automind.is_org_member(organization_id, array['owner', 'admin']) or automind.is_platform_admin())
  with check (automind.is_org_member(organization_id, array['owner', 'admin']) or automind.is_platform_admin());

-- consents / privacy requests ------------------------------------------------
create policy user_consents_own on automind.user_consents for select to automind_app
  using (user_id = automind.current_user_id() or automind.is_platform_staff());
create policy user_consents_insert on automind.user_consents for insert to automind_app
  with check (user_id = automind.current_user_id());
create policy data_requests_own on automind.data_requests for select to automind_app
  using (user_id = automind.current_user_id() or automind.is_platform_staff());
create policy data_requests_insert on automind.data_requests for insert to automind_app
  with check (user_id = automind.current_user_id() and status = 'pending');
create policy data_requests_admin on automind.data_requests for update to automind_app
  using (automind.is_platform_admin()) with check (automind.is_platform_admin());

-- vehicles -------------------------------------------------------------------
create policy vehicles_select on automind.vehicles for select to automind_app
  using (owner_user_id = automind.current_user_id()
         or (organization_id is not null and automind.is_org_member(organization_id))
         or automind.is_platform_staff());
create policy vehicles_insert on automind.vehicles for insert to automind_app
  with check ((owner_user_id = automind.current_user_id() and organization_id is null)
              or (organization_id is not null and automind.is_org_member(organization_id, array['owner', 'admin', 'technician', 'advisor'])));
create policy vehicles_update on automind.vehicles for update to automind_app
  using (automind.can_write_vehicle(id)) with check (automind.can_write_vehicle(id));
create policy vehicles_delete on automind.vehicles for delete to automind_app
  using (owner_user_id = automind.current_user_id()
         or (organization_id is not null and automind.is_org_member(organization_id, array['owner', 'admin'])));

create policy vehicle_profiles_select on automind.vehicle_profiles for select to automind_app
  using (automind.can_access_vehicle(vehicle_id));
create policy vehicle_profiles_write on automind.vehicle_profiles for all to automind_app
  using (automind.can_write_vehicle(vehicle_id)) with check (automind.can_write_vehicle(vehicle_id));

-- devices & connections --------------------------------------------------------
create policy obd_devices_select on automind.obd_devices for select to automind_app
  using (owner_user_id = automind.current_user_id()
         or (organization_id is not null and automind.is_org_member(organization_id))
         or automind.is_platform_staff());
create policy obd_devices_write on automind.obd_devices for all to automind_app
  using (owner_user_id = automind.current_user_id()
         or (organization_id is not null and automind.is_org_member(organization_id, array['owner', 'admin', 'technician'])))
  with check ((owner_user_id = automind.current_user_id()
               or (organization_id is not null and automind.is_org_member(organization_id, array['owner', 'admin', 'technician']))));

-- Certification is a platform decision, not something an owner can set.
create or replace function automind.guard_device_certification()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user = 'automind_app' and not automind.is_platform_admin()
     and new.is_certified and (tg_op = 'INSERT' or not old.is_certified) then
    raise exception 'device certification requires platform approval' using errcode = '42501';
  end if;
  return new;
end;
$$;
create trigger obd_devices_guard_cert before insert or update on automind.obd_devices
  for each row execute function automind.guard_device_certification();

create policy vehicle_connections_select on automind.vehicle_connections for select to automind_app
  using (user_id = automind.current_user_id() or automind.is_platform_staff());
create policy vehicle_connections_insert on automind.vehicle_connections for insert to automind_app
  with check (user_id = automind.current_user_id());
create policy vehicle_connections_update on automind.vehicle_connections for update to automind_app
  using (user_id = automind.current_user_id()) with check (user_id = automind.current_user_id());

-- diagnostic sessions & children ----------------------------------------------
create policy sessions_select on automind.diagnostic_sessions for select to automind_app
  using (automind.can_access_session(id));
create policy sessions_insert on automind.diagnostic_sessions for insert to automind_app
  with check (user_id = automind.current_user_id()
              and (vehicle_id is null or automind.can_write_vehicle(vehicle_id))
              and (organization_id is null or automind.is_org_member(organization_id, array['owner', 'admin', 'technician'])));
create policy sessions_update on automind.diagnostic_sessions for update to automind_app
  using (automind.can_write_session(id)) with check (automind.can_write_session(id));
create policy sessions_delete on automind.diagnostic_sessions for delete to automind_app
  using (user_id = automind.current_user_id());

do $$
declare
  t text;
begin
  foreach t in array array[
    'diagnostic_trouble_codes', 'telemetry_readings', 'telemetry_aggregates',
    'diagnostic_findings', 'ai_diagnoses', 'diagnosis_evidence'
  ] loop
    execute format(
      'create policy %I on automind.%I for select to automind_app using (automind.can_access_session(session_id))',
      t || '_select', t);
    execute format(
      'create policy %I on automind.%I for insert to automind_app with check (automind.can_write_session(session_id))',
      t || '_insert', t);
    execute format(
      'create policy %I on automind.%I for update to automind_app using (automind.can_write_session(session_id)) with check (automind.can_write_session(session_id))',
      t || '_update', t);
    execute format(
      'create policy %I on automind.%I for delete to automind_app using (automind.can_write_session(session_id))',
      t || '_delete', t);
  end loop;
end;
$$;

create policy recordings_select on automind.telemetry_recordings for select to automind_app
  using (user_id = automind.current_user_id()
         or (session_id is not null and automind.can_access_session(session_id)));
create policy recordings_write on automind.telemetry_recordings for all to automind_app
  using (user_id = automind.current_user_id())
  with check (user_id = automind.current_user_id());

-- reference / catalogue data: readable by any signed-in user, admin-managed ----
do $$
declare
  t text;
begin
  foreach t in array array[
    'manufacturer_packs', 'dtc_definitions', 'service_procedures', 'procedure_allowlist',
    'subscription_plans', 'parts', 'vehicle_part_fitments'
  ] loop
    execute format(
      'create policy %I on automind.%I for select to automind_app using (automind.current_user_id() is not null)',
      t || '_read', t);
    execute format(
      'create policy %I on automind.%I for all to automind_app using (automind.is_platform_admin()) with check (automind.is_platform_admin())',
      t || '_admin', t);
  end loop;
end;
$$;

-- control operations: own records; inserts must carry consent ------------------
create policy control_ops_select on automind.control_operations for select to automind_app
  using (user_id = automind.current_user_id() or automind.is_platform_staff());
create policy control_ops_insert on automind.control_operations for insert to automind_app
  with check (user_id = automind.current_user_id() and length(consent_text) > 0);
create policy control_ops_update on automind.control_operations for update to automind_app
  using (user_id = automind.current_user_id()) with check (user_id = automind.current_user_id());

-- maintenance ------------------------------------------------------------------
create policy maintenance_select on automind.maintenance_records for select to automind_app
  using (automind.can_access_vehicle(vehicle_id)
         or (organization_id is not null and automind.is_org_member(organization_id)));
create policy maintenance_write on automind.maintenance_records for all to automind_app
  using (automind.can_write_vehicle(vehicle_id)
         or (organization_id is not null and automind.is_org_member(organization_id, array['owner', 'admin', 'technician', 'advisor'])))
  with check (automind.can_write_vehicle(vehicle_id)
         or (organization_id is not null and automind.is_org_member(organization_id, array['owner', 'admin', 'technician', 'advisor'])));

-- garage -----------------------------------------------------------------------
create policy workshops_select on automind.workshops for select to automind_app
  using (status = 'active' or automind.is_org_member(organization_id) or automind.is_platform_staff());
create policy workshops_write on automind.workshops for all to automind_app
  using (automind.is_org_member(organization_id, array['owner', 'admin']) or automind.is_platform_admin())
  with check (automind.is_org_member(organization_id, array['owner', 'admin']) or automind.is_platform_admin());

create policy report_shares_select on automind.report_shares for select to automind_app
  using (owner_user_id = automind.current_user_id()
         or (revoked_at is null and expires_at > now() and automind.is_org_member(shared_with_org_id)));
create policy report_shares_insert on automind.report_shares for insert to automind_app
  with check (owner_user_id = automind.current_user_id()
              and exists (select 1 from automind.diagnostic_sessions s
                          where s.id = session_id and s.user_id = automind.current_user_id()));
create policy report_shares_update on automind.report_shares for update to automind_app
  using (owner_user_id = automind.current_user_id()) with check (owner_user_id = automind.current_user_id());

create policy bookings_select on automind.workshop_bookings for select to automind_app
  using (customer_user_id = automind.current_user_id()
         or automind.is_org_member(automind.workshop_org(workshop_id))
         or automind.is_platform_staff());
create policy bookings_insert on automind.workshop_bookings for insert to automind_app
  with check (customer_user_id = automind.current_user_id());
create policy bookings_update on automind.workshop_bookings for update to automind_app
  using (customer_user_id = automind.current_user_id()
         or automind.is_org_member(automind.workshop_org(workshop_id), array['owner', 'admin', 'advisor', 'technician']))
  with check (customer_user_id = automind.current_user_id()
         or automind.is_org_member(automind.workshop_org(workshop_id), array['owner', 'admin', 'advisor', 'technician']));

create policy quotes_select on automind.repair_quotes for select to automind_app
  using ((customer_user_id = automind.current_user_id() and status <> 'draft')
         or automind.is_org_member(automind.workshop_org(workshop_id))
         or automind.is_platform_staff());
create policy quotes_workshop_write on automind.repair_quotes for all to automind_app
  using (automind.is_org_member(automind.workshop_org(workshop_id), array['owner', 'admin', 'advisor']))
  with check (automind.is_org_member(automind.workshop_org(workshop_id), array['owner', 'admin', 'advisor']));
create policy quotes_customer_respond on automind.repair_quotes for update to automind_app
  using (customer_user_id = automind.current_user_id() and status = 'sent')
  with check (customer_user_id = automind.current_user_id() and status in ('accepted', 'rejected'));

create policy reviews_select on automind.workshop_reviews for select to automind_app
  using (automind.current_user_id() is not null);
create policy reviews_insert on automind.workshop_reviews for insert to automind_app
  with check (user_id = automind.current_user_id()
              and exists (select 1 from automind.workshop_bookings b
                          where b.id = booking_id and b.customer_user_id = automind.current_user_id()
                            and b.status = 'completed' and b.workshop_id = workshop_reviews.workshop_id));

-- parts --------------------------------------------------------------------------
create policy suppliers_select on automind.suppliers for select to automind_app
  using (status = 'active' or automind.is_org_member(organization_id) or automind.is_platform_staff());
create policy suppliers_write on automind.suppliers for all to automind_app
  using (automind.is_org_member(organization_id, array['owner', 'admin']) or automind.is_platform_admin())
  with check (automind.is_org_member(organization_id, array['owner', 'admin']) or automind.is_platform_admin());

create policy inventory_select on automind.supplier_inventory for select to automind_app
  using (automind.current_user_id() is not null);
create policy inventory_write on automind.supplier_inventory for all to automind_app
  using (automind.is_org_member(automind.supplier_org(supplier_id), array['owner', 'admin']))
  with check (automind.is_org_member(automind.supplier_org(supplier_id), array['owner', 'admin']));

create policy parts_orders_select on automind.parts_orders for select to automind_app
  using (user_id = automind.current_user_id()
         or automind.is_org_member(automind.supplier_org(supplier_id))
         or automind.is_platform_staff());
create policy parts_orders_insert on automind.parts_orders for insert to automind_app
  with check (user_id = automind.current_user_id() and status = 'pending');
create policy parts_orders_update on automind.parts_orders for update to automind_app
  using (user_id = automind.current_user_id() or automind.is_org_member(automind.supplier_org(supplier_id), array['owner', 'admin']))
  with check (user_id = automind.current_user_id() or automind.is_org_member(automind.supplier_org(supplier_id), array['owner', 'admin']));

create policy order_items_select on automind.parts_order_items for select to automind_app
  using (exists (select 1 from automind.parts_orders o where o.id = order_id));   -- inherits parts_orders RLS
create policy order_items_insert on automind.parts_order_items for insert to automind_app
  with check (exists (select 1 from automind.parts_orders o
                      where o.id = order_id and o.user_id = automind.current_user_id() and o.status = 'pending'));

-- commerce --------------------------------------------------------------------------
create policy subscriptions_select on automind.subscriptions for select to automind_app
  using (user_id = automind.current_user_id()
         or (organization_id is not null and automind.is_org_member(organization_id, array['owner', 'admin']))
         or automind.is_platform_staff());
create policy subscriptions_admin on automind.subscriptions for all to automind_app
  using (automind.is_platform_admin()) with check (automind.is_platform_admin());

create policy payments_select on automind.payments for select to automind_app
  using (user_id = automind.current_user_id()
         or (organization_id is not null and automind.is_org_member(organization_id, array['owner', 'admin']))
         or automind.is_platform_staff());
create policy payments_admin on automind.payments for all to automind_app
  using (automind.is_platform_admin()) with check (automind.is_platform_admin());

create policy notifications_own on automind.notifications for select to automind_app
  using (user_id = automind.current_user_id());
create policy notifications_mark_read on automind.notifications for update to automind_app
  using (user_id = automind.current_user_id()) with check (user_id = automind.current_user_id());

-- audit: anyone can append their own entry, only staff can read -------------------
create policy audit_insert on automind.audit_logs for insert to automind_app
  with check (actor_user_id is null or actor_user_id = automind.current_user_id());
create policy audit_select on automind.audit_logs for select to automind_app
  using (automind.is_platform_staff());

-- Default privileges for future tables created by the migration owner.
alter default privileges in schema automind grant select, insert, update, delete on tables to automind_app;
alter default privileges in schema automind grant usage, select on sequences to automind_app;
