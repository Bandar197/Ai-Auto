-- Live lobby numbers and username availability check (used by onboarding).
create or replace function public.lobby_stats() returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'online', (select count(*) from public.account_private where last_seen > now() - interval '2 minutes'),
    'playing', (select count(*) from public.rooms where status = 'playing'),
    'open_rooms', (select count(*) from public.rooms where kind = 'public' and status = 'waiting' and updated_at > now() - interval '2 hours'),
    'queue_ranked', (select count(*) from public.queue where mode = 'ranked' and matched_room is null),
    'queue_friendly', (select count(*) from public.queue where mode = 'friendly' and matched_room is null)) $$;
grant execute on function public.lobby_stats() to anon, authenticated;

create or replace function public.username_available(p_username text) returns boolean
language sql stable security definer set search_path = '' as $$
  select public.valid_username(btrim(p_username)) and not exists (select 1 from public.profiles where lower(username) = lower(btrim(p_username)) and id <> coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000'::uuid)) $$;
