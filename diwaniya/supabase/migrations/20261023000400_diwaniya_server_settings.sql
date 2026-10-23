-- Server-only settings and the scheduled sweep.
-- owner_email: the account that becomes owner on first sign-in (change it with SQL; clients cannot read this table).
-- The sweep secret is generated inside Supabase Vault and never leaves the database.
create table if not exists public.app_settings (key text primary key, value text not null, updated_at timestamptz not null default now());
alter table public.app_settings enable row level security;
insert into public.app_settings (key, value) values ('owner_email', 'owner@example.com') on conflict (key) do nothing;

select vault.create_secret(encode(extensions.gen_random_bytes(24), 'hex'), 'diwaniya_cron_secret', 'Shared secret for the scheduled sweep')
where not exists (select 1 from vault.secrets where name = 'diwaniya_cron_secret');

create or replace function public.cron_secret_ok(p text) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from vault.decrypted_secrets where name = 'diwaniya_cron_secret' and decrypted_secret = p) $$;
revoke execute on function public.cron_secret_ok(text) from public, anon, authenticated;

create extension if not exists pg_cron;
-- Replace YOUR-PROJECT with the project ref.
select cron.schedule('diwaniya-sweep', '* * * * *', $cron$
  select net.http_post(
    url := 'https://YOUR-PROJECT.supabase.co/functions/v1/api',
    headers := jsonb_build_object('Content-Type', 'application/json',
      'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'diwaniya_cron_secret')),
    body := '{"action":"sweep"}'::jsonb, timeout_milliseconds := 55000)
$cron$);
