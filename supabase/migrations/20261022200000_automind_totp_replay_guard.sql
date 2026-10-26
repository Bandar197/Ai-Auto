-- TOTP replay protection: remember the last accepted 30-second step per user, so a
-- code that was already used (e.g. seen over someone's shoulder) cannot be used again.
alter table automind.users add column if not exists mfa_last_used_step bigint;

comment on column automind.users.mfa_last_used_step is
  'Last accepted TOTP time step (unix time / 30). A code is accepted only for a later step.';

-- Users may not reset it themselves through the app role (only the API''s system path updates it).
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
       or new.locked_until is distinct from old.locked_until
       or new.mfa_last_used_step is distinct from old.mfa_last_used_step then
      raise exception 'not allowed to change protected user fields' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;
