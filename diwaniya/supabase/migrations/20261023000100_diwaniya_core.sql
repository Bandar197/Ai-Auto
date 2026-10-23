-- Diwaniya core schema: profiles, privacy, social graph, notifications, rooms, matches, progression, moderation.
-- All writes that need validation go through SECURITY DEFINER functions (search_path = '') or the `api` Edge Function.

------------------------------------------------------------------------------------------------
-- Profiles (public data). Private account data lives in account_private.
------------------------------------------------------------------------------------------------
alter table public.profiles
  add column if not exists player_no bigint generated always as identity (start with 100001),
  add column if not exists display_name text,
  add column if not exists avatar_url text,
  add column if not exists bio text not null default '',
  add column if not exists xp int not null default 0,
  add column if not exists level int not null default 1,
  add column if not exists losses int not null default 0,
  add column if not exists sun_rounds int not null default 0,
  add column if not exists sun_won int not null default 0,
  add column if not exists hokm_rounds int not null default 0,
  add column if not exists hokm_won int not null default 0,
  add column if not exists cur_streak int not null default 0,
  add column if not exists best_streak int not null default 0,
  add column if not exists ranked_games int not null default 0,
  add column if not exists privacy_online text not null default 'everyone',
  add column if not exists privacy_history text not null default 'everyone',
  add column if not exists privacy_requests text not null default 'everyone',
  add column if not exists privacy_invites text not null default 'friends',
  add column if not exists equip_table text not null default 'classic',
  add column if not exists equip_back text not null default 'sadu',
  add column if not exists equip_frame text not null default 'none',
  add column if not exists updated_at timestamptz not null default now();

alter table public.profiles add constraint profiles_display_len check (display_name is null or char_length(display_name) between 1 and 24);
alter table public.profiles add constraint profiles_bio_len check (char_length(bio) <= 160);
alter table public.profiles add constraint profiles_priv_online check (privacy_online in ('everyone','friends','nobody'));
alter table public.profiles add constraint profiles_priv_history check (privacy_history in ('everyone','friends','nobody'));
alter table public.profiles add constraint profiles_priv_requests check (privacy_requests in ('everyone','nobody'));
alter table public.profiles add constraint profiles_priv_invites check (privacy_invites in ('everyone','friends','nobody'));
create unique index if not exists profiles_player_no on public.profiles (player_no);

revoke insert, update, delete on public.profiles from anon, authenticated;
grant update (display_name, bio, avatar_url, privacy_online, privacy_history, privacy_requests, privacy_invites, equip_table, equip_back, equip_frame)
  on public.profiles to authenticated;
create policy "owner edits own profile" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create table public.account_private (
  user_id uuid primary key references auth.users on delete cascade,
  last_seen timestamptz,
  ban_until timestamptz,
  ban_permanent boolean not null default false,
  ban_reason text,
  notify_requests boolean not null default true,
  notify_invites boolean not null default true,
  notify_results boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.account_private enable row level security;
create policy "own private row" on public.account_private for select to authenticated using (user_id = (select auth.uid()));
create policy "own notify settings" on public.account_private for update to authenticated using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
revoke insert, update, delete on public.account_private from anon, authenticated;
grant update (notify_requests, notify_invites, notify_results) on public.account_private to authenticated;

------------------------------------------------------------------------------------------------
-- Cosmetics, achievements, challenges, seasons (catalogues are public)
------------------------------------------------------------------------------------------------
create table public.cosmetics (
  code text primary key, kind text not null check (kind in ('table','back','frame')),
  name text not null, unlock text not null default 'default', sort int not null default 0
);
create table public.user_cosmetics (
  user_id uuid references auth.users on delete cascade, code text references public.cosmetics on delete cascade,
  unlocked_at timestamptz not null default now(), primary key (user_id, code)
);
create table public.achievements (
  code text primary key, name text not null, description text not null, icon text not null, xp int not null default 0,
  reward_cosmetic text references public.cosmetics, sort int not null default 0
);
create table public.user_achievements (
  user_id uuid references auth.users on delete cascade, code text references public.achievements on delete cascade,
  unlocked_at timestamptz not null default now(), primary key (user_id, code)
);
create table public.challenges (
  id serial primary key, code text unique not null, period text not null check (period in ('daily','weekly')),
  title text not null, metric text not null, target int not null, reward_xp int not null default 0,
  reward_cosmetic text references public.cosmetics, active boolean not null default true
);
create table public.user_challenges (
  user_id uuid references auth.users on delete cascade, challenge_id int references public.challenges on delete cascade,
  period_key text not null, progress int not null default 0, completed_at timestamptz,
  primary key (user_id, challenge_id, period_key)
);
create table public.seasons (
  id serial primary key, name text not null, starts_at timestamptz not null default now(), ends_at timestamptz,
  active boolean not null default false
);
create unique index seasons_one_active on public.seasons (active) where active;
create table public.season_stats (
  season_id int references public.seasons on delete cascade, user_id uuid references auth.users on delete cascade,
  rating int not null default 1000, games int not null default 0, wins int not null default 0,
  primary key (season_id, user_id)
);
alter table public.cosmetics enable row level security;
alter table public.user_cosmetics enable row level security;
alter table public.achievements enable row level security;
alter table public.user_achievements enable row level security;
alter table public.challenges enable row level security;
alter table public.user_challenges enable row level security;
alter table public.seasons enable row level security;
alter table public.season_stats enable row level security;
create policy "catalogue" on public.cosmetics for select to anon, authenticated using (true);
create policy "catalogue" on public.achievements for select to anon, authenticated using (true);
create policy "catalogue" on public.challenges for select to anon, authenticated using (true);
create policy "catalogue" on public.seasons for select to anon, authenticated using (true);
create policy "public badges" on public.user_achievements for select to anon, authenticated using (true);
create policy "public season table" on public.season_stats for select to anon, authenticated using (true);
create policy "own cosmetics" on public.user_cosmetics for select to authenticated using (user_id = (select auth.uid()));
create policy "own challenges" on public.user_challenges for select to authenticated using (user_id = (select auth.uid()));

------------------------------------------------------------------------------------------------
-- Social graph
------------------------------------------------------------------------------------------------
create table public.friend_requests (
  id bigint generated always as identity primary key,
  from_id uuid not null references auth.users on delete cascade,
  to_id uuid not null references auth.users on delete cascade,
  status text not null default 'pending' check (status in ('pending','accepted','declined','cancelled')),
  created_at timestamptz not null default now(), responded_at timestamptz,
  check (from_id <> to_id)
);
create unique index friend_requests_pending on public.friend_requests (least(from_id, to_id), greatest(from_id, to_id)) where status = 'pending';
create table public.friendships (
  a uuid not null references auth.users on delete cascade,
  b uuid not null references auth.users on delete cascade,
  created_at timestamptz not null default now(),
  primary key (a, b), check (a < b)
);
create table public.blocks (
  blocker uuid not null references auth.users on delete cascade,
  blocked uuid not null references auth.users on delete cascade,
  created_at timestamptz not null default now(), primary key (blocker, blocked), check (blocker <> blocked)
);
create table public.user_mutes (
  muter uuid not null references auth.users on delete cascade,
  muted uuid not null references auth.users on delete cascade,
  created_at timestamptz not null default now(), primary key (muter, muted)
);
create table public.notifications (
  id bigint generated always as identity primary key,
  user_id uuid not null references auth.users on delete cascade,
  kind text not null, data jsonb not null default '{}', created_at timestamptz not null default now(), read_at timestamptz
);
create index notifications_user on public.notifications (user_id, id desc);
alter table public.friend_requests enable row level security;
alter table public.friendships enable row level security;
alter table public.blocks enable row level security;
alter table public.user_mutes enable row level security;
alter table public.notifications enable row level security;
create policy "my requests" on public.friend_requests for select to authenticated using ((select auth.uid()) in (from_id, to_id));
create policy "my friendships" on public.friendships for select to authenticated using ((select auth.uid()) in (a, b));
create policy "my blocks" on public.blocks for select to authenticated using (blocker = (select auth.uid()));
create policy "my mutes read" on public.user_mutes for select to authenticated using (muter = (select auth.uid()));
create policy "my mutes add" on public.user_mutes for insert to authenticated with check (muter = (select auth.uid()));
create policy "my mutes remove" on public.user_mutes for delete to authenticated using (muter = (select auth.uid()));
create policy "my notifications" on public.notifications for select to authenticated using (user_id = (select auth.uid()));

------------------------------------------------------------------------------------------------
-- Rooms and live games
------------------------------------------------------------------------------------------------
create table public.rooms (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  kind text not null check (kind in ('private','public','ranked','friendly')),
  owner uuid references auth.users on delete set null,
  status text not null default 'waiting' check (status in ('waiting','playing','finished','closed')),
  rules jsonb not null,
  chat_mode text not null default 'open' check (chat_mode in ('open','quick','off')),
  seats jsonb not null default '[null,null,null,null]',
  members uuid[] not null default '{}',
  match_id uuid,
  state jsonb,
  version int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index rooms_lobby on public.rooms (kind, status, updated_at desc);
create table public.room_secrets (room_id uuid primary key references public.rooms on delete cascade, g jsonb, meta jsonb not null default '{}');
create table public.room_hands (
  room_id uuid not null references public.rooms on delete cascade, seat int not null check (seat between 0 and 3),
  user_id uuid, cards text[] not null default '{}', primary key (room_id, seat)
);
create table public.chat_messages (
  id bigint generated always as identity primary key,
  room_id uuid not null references public.rooms on delete cascade,
  user_id uuid not null references auth.users on delete cascade,
  body text not null check (char_length(body) between 1 and 200),
  hidden boolean not null default false,
  created_at timestamptz not null default now()
);
create index chat_room on public.chat_messages (room_id, id desc);
create index chat_user_time on public.chat_messages (user_id, created_at desc);
alter table public.rooms enable row level security;
alter table public.room_secrets enable row level security;
alter table public.room_hands enable row level security;
alter table public.chat_messages enable row level security;
create policy "visible rooms" on public.rooms for select to authenticated
  using (kind = 'public' or (select auth.uid()) = any(members));
create policy "own hand only" on public.room_hands for select to authenticated using (user_id = (select auth.uid()));
create policy "room chat" on public.chat_messages for select to authenticated using (
  not hidden
  and exists (select 1 from public.rooms r where r.id = room_id and (select auth.uid()) = any(r.members))
  and not exists (select 1 from public.blocks b where b.blocker = (select auth.uid()) and b.blocked = user_id)
);

------------------------------------------------------------------------------------------------
-- Matches (permanent record)
------------------------------------------------------------------------------------------------
create table public.matches (
  id uuid primary key default gen_random_uuid(),
  room_id uuid references public.rooms on delete set null,
  ranked boolean not null default false,
  season_id int references public.seasons,
  rules jsonb not null,
  players jsonb not null,                 -- [{seat, uid, name}]
  player_ids uuid[] not null,
  status text not null default 'playing' check (status in ('playing','finished','abandoned')),
  score0 int, score1 int, winner_team int,
  rounds jsonb not null default '[]',
  started_at timestamptz not null default now(), ended_at timestamptz,
  recorded boolean not null default false
);
create index matches_players on public.matches using gin (player_ids);
create table public.match_events (
  id bigint generated always as identity primary key,
  match_id uuid not null references public.matches on delete cascade,
  seq int not null, kind text not null, data jsonb not null default '[]', created_at timestamptz not null default now(),
  unique (match_id, seq)
);
create table public.match_players (
  match_id uuid not null references public.matches on delete cascade,
  user_id uuid not null,
  seat int not null, team int not null,
  result text not null check (result in ('win','loss')),
  abandoned boolean not null default false,
  rating_before int, rating_after int, xp_gained int not null default 0,
  primary key (match_id, user_id)
);
create index match_players_user on public.match_players (user_id, match_id);
alter table public.matches enable row level security;
alter table public.match_events enable row level security;
alter table public.match_players enable row level security;
create policy "own matches" on public.matches for select to authenticated using ((select auth.uid()) = any(player_ids));
create policy "events after the match" on public.match_events for select to authenticated using (
  exists (select 1 from public.matches m where m.id = match_id and m.status <> 'playing' and (select auth.uid()) = any(m.player_ids))
);
create policy "own match rows" on public.match_players for select to authenticated using (user_id = (select auth.uid()));

------------------------------------------------------------------------------------------------
-- Matchmaking, moderation, administration
------------------------------------------------------------------------------------------------
create table public.queue (
  user_id uuid primary key references auth.users on delete cascade,
  mode text not null check (mode in ('ranked','friendly')),
  rating int not null, created_at timestamptz not null default now()
);
create table public.reports (
  id bigint generated always as identity primary key,
  reporter uuid not null references auth.users on delete cascade,
  kind text not null check (kind in ('user','message','match')),
  target_user uuid, ref_id text, reason text not null, details text not null default '' check (char_length(details) <= 500),
  status text not null default 'open' check (status in ('open','resolved','dismissed')),
  created_at timestamptz not null default now(), resolved_by uuid, resolved_at timestamptz, resolution text
);
create table public.admin_roles (
  user_id uuid primary key references auth.users on delete cascade,
  role text not null check (role in ('owner','admin','moderator')),
  granted_at timestamptz not null default now(), granted_by uuid
);
create table public.audit_log (
  id bigint generated always as identity primary key, actor uuid, action text not null, target text, details jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create table public.server_errors (
  id bigint generated always as identity primary key, at timestamptz not null default now(), source text not null, message text not null, context jsonb not null default '{}'
);
alter table public.queue enable row level security;
alter table public.reports enable row level security;
alter table public.admin_roles enable row level security;
alter table public.audit_log enable row level security;
alter table public.server_errors enable row level security;
create policy "own queue row" on public.queue for select to authenticated using (user_id = (select auth.uid()));
create policy "own reports" on public.reports for select to authenticated using (reporter = (select auth.uid()));
create policy "own role" on public.admin_roles for select to authenticated using (user_id = (select auth.uid()));

alter publication supabase_realtime add table public.rooms, public.room_hands, public.chat_messages, public.notifications;

------------------------------------------------------------------------------------------------
-- Avatars bucket: images only, 1 MB, each user writes only inside their own folder
------------------------------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('avatars', 'avatars', true, 1048576, array['image/webp','image/png','image/jpeg'])
on conflict (id) do update set public = true, file_size_limit = 1048576, allowed_mime_types = array['image/webp','image/png','image/jpeg'];
create policy "avatar upload own folder" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "avatar update own folder" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "avatar delete own folder" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
