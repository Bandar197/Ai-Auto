-- Diwaniya server-side functions. Every function uses SECURITY DEFINER with an empty search_path and checks auth.uid() itself.
-- Errors are raised with short English codes; the web client maps them to Arabic messages.

alter table public.account_private add column if not exists username_changed_at timestamptz;

------------------------------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------------------------------
create or replace function public.role_rank(p_role text) returns int language sql immutable set search_path = '' as $$
  select case p_role when 'owner' then 3 when 'admin' then 2 when 'moderator' then 1 else 0 end $$;

create or replace function public.is_staff(p_uid uuid, p_min text default 'moderator') returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.admin_roles r where r.user_id = p_uid and public.role_rank(r.role) >= public.role_rank(p_min)) $$;

create or replace function public.blocked_either(a uuid, b uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.blocks where (blocker = a and blocked = b) or (blocker = b and blocked = a)) $$;

create or replace function public.are_friends(x uuid, y uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.friendships where a = least(x, y) and b = greatest(x, y)) $$;

create or replace function public.level_for(p_xp int) returns int language sql immutable set search_path = '' as $$
  select greatest(1, floor((1 + sqrt(1 + 8 * greatest(p_xp, 0) / 100.0)) / 2)::int) $$;

create or replace function public.is_banned(p_uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.account_private a where a.user_id = p_uid and (a.ban_permanent or a.ban_until > now())) $$;

create or replace function public.require_uid() returns uuid language plpgsql stable set search_path = '' as $$
declare v uuid := auth.uid();
begin
  if v is null then raise exception 'not_signed_in'; end if;
  return v;
end $$;

create or replace function public.notify_user(p_user uuid, p_kind text, p_data jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.notifications (user_id, kind, data) values (p_user, p_kind, coalesce(p_data, '{}'::jsonb));
end $$;

create or replace function public.online_visible(p_owner uuid, p_viewer uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select case (select privacy_online from public.profiles where id = p_owner)
    when 'everyone' then true
    when 'friends' then p_owner = p_viewer or public.are_friends(p_owner, p_viewer)
    else p_owner = p_viewer end $$;

create or replace function public.is_online(p_uid uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select coalesce((select last_seen > now() - interval '90 seconds' from public.account_private where user_id = p_uid), false) $$;

create or replace function public.profile_card(p_uid uuid, p_viewer uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('id', p.id, 'username', p.username, 'display_name', coalesce(p.display_name, p.username), 'avatar_url', p.avatar_url,
    'player_no', p.player_no, 'level', p.level, 'rating', p.rating, 'frame', p.equip_frame,
    'online', case when public.online_visible(p.id, p_viewer) then public.is_online(p.id) else null end)
  from public.profiles p where p.id = p_uid $$;

------------------------------------------------------------------------------------------------
-- onboarding and profile
------------------------------------------------------------------------------------------------
create or replace function public.valid_username(p text) returns boolean language sql immutable set search_path = '' as $$
  select p ~ '^[A-Za-z0-9_ء-ي٠-٩]{3,14}$' $$;

create or replace function public.check_avatar_url(p_uid uuid, p_url text) returns boolean language sql immutable set search_path = '' as $$
  select p_url is null or p_url ~ ('^https://[a-z0-9]+\.supabase\.co/storage/v1/object/public/avatars/' || p_uid::text || '/[A-Za-z0-9_.-]+(\?v=[0-9]+)?$') $$;

create or replace function public.complete_onboarding(p_username text, p_display text, p_avatar_url text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := public.require_uid(); disp text := btrim(coalesce(p_display, ''));
begin
  p_username := btrim(coalesce(p_username, ''));
  if not public.valid_username(p_username) then raise exception 'bad_username'; end if;
  if char_length(disp) < 1 or char_length(disp) > 24 then raise exception 'bad_display_name'; end if;
  if not public.check_avatar_url(uid, p_avatar_url) then raise exception 'bad_avatar'; end if;
  if exists (select 1 from public.profiles where lower(username) = lower(p_username) and id <> uid) then raise exception 'username_taken'; end if;
  insert into public.profiles (id, username, display_name, avatar_url) values (uid, p_username, disp, p_avatar_url)
  on conflict (id) do update set username = excluded.username, display_name = excluded.display_name, avatar_url = excluded.avatar_url, updated_at = now();
  insert into public.account_private (user_id) values (uid) on conflict (user_id) do nothing;
  insert into public.user_cosmetics (user_id, code) select uid, code from public.cosmetics where unlock = 'default' on conflict do nothing;
  return public.profile_card(uid, uid);
end $$;

create or replace function public.change_username(p_username text) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := public.require_uid(); last timestamptz;
begin
  p_username := btrim(coalesce(p_username, ''));
  if not public.valid_username(p_username) then raise exception 'bad_username'; end if;
  select username_changed_at into last from public.account_private where user_id = uid;
  if last is not null and last > now() - interval '7 days' then raise exception 'username_change_cooldown'; end if;
  if exists (select 1 from public.profiles where lower(username) = lower(p_username) and id <> uid) then raise exception 'username_taken'; end if;
  update public.profiles set username = p_username, updated_at = now() where id = uid;
  update public.account_private set username_changed_at = now() where user_id = uid;
end $$;

create or replace function public.profiles_guard() returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not public.check_avatar_url(new.id, new.avatar_url) then raise exception 'bad_avatar'; end if;
  if new.display_name is not null then new.display_name := btrim(new.display_name); end if;
  new.bio := btrim(coalesce(new.bio, ''));
  if new.equip_table is distinct from old.equip_table and not exists (select 1 from public.user_cosmetics u join public.cosmetics c using (code) where u.user_id = new.id and u.code = new.equip_table and c.kind = 'table') then raise exception 'not_unlocked'; end if;
  if new.equip_back is distinct from old.equip_back and not exists (select 1 from public.user_cosmetics u join public.cosmetics c using (code) where u.user_id = new.id and u.code = new.equip_back and c.kind = 'back') then raise exception 'not_unlocked'; end if;
  if new.equip_frame is distinct from old.equip_frame and not exists (select 1 from public.user_cosmetics u join public.cosmetics c using (code) where u.user_id = new.id and u.code = new.equip_frame and c.kind = 'frame') then raise exception 'not_unlocked'; end if;
  new.updated_at := now();
  return new;
end $$;
create trigger profiles_guard before update on public.profiles for each row execute function public.profiles_guard();

create or replace function public.touch() returns jsonb language plpgsql security definer set search_path = '' as $$
declare uid uuid := public.require_uid(); a public.account_private;
begin
  update public.account_private set last_seen = now() where user_id = uid returning * into a;
  return jsonb_build_object(
    'unread', (select count(*) from public.notifications where user_id = uid and read_at is null),
    'banned', coalesce(a.ban_permanent or a.ban_until > now(), false), 'ban_until', a.ban_until, 'ban_reason', a.ban_reason,
    'staff', (select role from public.admin_roles where user_id = uid));
end $$;

create or replace function public.get_profile(p_username text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v uuid := auth.uid(); p public.profiles; hist boolean; rel jsonb; out_req bigint; in_req bigint; season jsonb;
begin
  select * into p from public.profiles where lower(username) = lower(btrim(p_username));
  if not found then return null; end if;
  hist := case p.privacy_history when 'everyone' then true when 'friends' then v = p.id or public.are_friends(p.id, v) else v = p.id end;
  select id into out_req from public.friend_requests where from_id = v and to_id = p.id and status = 'pending';
  select id into in_req from public.friend_requests where from_id = p.id and to_id = v and status = 'pending';
  rel := jsonb_build_object('self', v = p.id, 'friend', public.are_friends(p.id, v),
    'blocked_by_me', exists (select 1 from public.blocks where blocker = v and blocked = p.id),
    'blocks_me', exists (select 1 from public.blocks where blocker = p.id and blocked = v),
    'muted', exists (select 1 from public.user_mutes where muter = v and muted = p.id),
    'outgoing_request', out_req, 'incoming_request', in_req,
    'can_request', p.privacy_requests = 'everyone', 'can_invite', p.privacy_invites = 'everyone' or (p.privacy_invites = 'friends' and public.are_friends(p.id, v)));
  select jsonb_build_object('name', s.name, 'rating', st.rating, 'games', st.games, 'wins', st.wins) into season
    from public.seasons s left join public.season_stats st on st.season_id = s.id and st.user_id = p.id where s.active;
  return jsonb_build_object(
    'id', p.id, 'player_no', p.player_no, 'username', p.username, 'display_name', coalesce(p.display_name, p.username), 'avatar_url', p.avatar_url,
    'bio', p.bio, 'joined', p.created_at, 'xp', p.xp, 'level', p.level, 'rating', p.rating,
    'games', p.games, 'wins', p.wins, 'losses', p.losses, 'kaboots', p.kaboots, 'best_streak', p.best_streak, 'cur_streak', p.cur_streak,
    'sun_rounds', p.sun_rounds, 'sun_won', p.sun_won, 'hokm_rounds', p.hokm_rounds, 'hokm_won', p.hokm_won, 'ranked_games', p.ranked_games,
    'frame', p.equip_frame, 'table', p.equip_table, 'back', p.equip_back,
    'online', case when public.online_visible(p.id, v) then public.is_online(p.id) else null end,
    'history_visible', hist, 'relation', rel, 'season', season,
    'achievements', coalesce((select jsonb_agg(jsonb_build_object('code', a.code, 'name', a.name, 'icon', a.icon, 'description', a.description, 'at', ua.unlocked_at) order by ua.unlocked_at)
                              from public.user_achievements ua join public.achievements a on a.code = ua.code where ua.user_id = p.id), '[]'::jsonb));
end $$;

create or replace function public.player_history(p_user uuid, p_limit int default 20) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v uuid := auth.uid(); priv text;
begin
  select privacy_history into priv from public.profiles where id = p_user;
  if not (v = p_user or priv = 'everyone' or (priv = 'friends' and public.are_friends(p_user, v)) or public.is_staff(v)) then return null; end if;
  return coalesce((select jsonb_agg(x order by x->>'ended_at' desc) from (
    select jsonb_build_object('match_id', m.id, 'ended_at', m.ended_at, 'ranked', m.ranked, 'result', mp.result, 'abandoned', mp.abandoned,
      'us', case when mp.team = 0 then m.score0 else m.score1 end, 'them', case when mp.team = 0 then m.score1 else m.score0 end,
      'rating_delta', coalesce(mp.rating_after - mp.rating_before, 0), 'xp', mp.xp_gained) as x
    from public.match_players mp join public.matches m on m.id = mp.match_id
    where mp.user_id = p_user and m.status <> 'playing' order by m.ended_at desc limit least(greatest(p_limit, 1), 50)) t), '[]'::jsonb);
end $$;

create or replace function public.search_players(p_q text) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v uuid := public.require_uid(); q text := btrim(coalesce(p_q, ''));
begin
  if char_length(q) < 2 then return '[]'::jsonb; end if;
  return coalesce((select jsonb_agg(public.profile_card(p.id, v)) from (
    select id from public.profiles p
    where ((q ~ '^[0-9]+$' and p.player_no = q::bigint) or lower(p.username) like lower(replace(replace(q, '%', ''), '_', '\_')) || '%'
       or lower(coalesce(p.display_name, '')) like '%' || lower(replace(replace(q, '%', ''), '_', '\_')) || '%')
      and p.id <> v and not public.blocked_either(p.id, v)
    order by p.username limit 20) p), '[]'::jsonb);
end $$;

------------------------------------------------------------------------------------------------
-- friends, blocks, invites, notifications
------------------------------------------------------------------------------------------------
create or replace function public.friend_send(p_target uuid) returns text
language plpgsql security definer set search_path = '' as $$
declare uid uuid := public.require_uid(); t public.profiles; rev bigint;
begin
  if p_target = uid then raise exception 'self'; end if;
  select * into t from public.profiles where id = p_target;
  if not found then raise exception 'not_found'; end if;
  if public.blocked_either(uid, p_target) then raise exception 'blocked'; end if;
  if public.are_friends(uid, p_target) then raise exception 'already_friends'; end if;
  select id into rev from public.friend_requests where from_id = p_target and to_id = uid and status = 'pending';
  if rev is not null then perform public.friend_respond(rev, true); return 'accepted'; end if;
  if t.privacy_requests = 'nobody' then raise exception 'requests_closed'; end if;
  if exists (select 1 from public.friend_requests where from_id = uid and to_id = p_target and status = 'pending') then raise exception 'already_pending'; end if;
  if (select count(*) from public.friend_requests where from_id = uid and created_at > now() - interval '1 day') >= 40 then raise exception 'rate_limited'; end if;
  insert into public.friend_requests (from_id, to_id) values (uid, p_target) returning id into rev;
  perform public.notify_user(p_target, 'friend_request', jsonb_build_object('request_id', rev, 'from', public.profile_card(uid, p_target)));
  return 'sent';
end $$;

create or replace function public.friend_respond(p_id bigint, p_accept boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := public.require_uid(); r public.friend_requests;
begin
  select * into r from public.friend_requests where id = p_id and to_id = uid and status = 'pending' for update;
  if not found then raise exception 'not_found'; end if;
  update public.friend_requests set status = case when p_accept then 'accepted' else 'declined' end, responded_at = now() where id = p_id;
  if p_accept then
    if public.blocked_either(r.from_id, uid) then raise exception 'blocked'; end if;
    insert into public.friendships (a, b) values (least(r.from_id, uid), greatest(r.from_id, uid)) on conflict do nothing;
    perform public.notify_user(r.from_id, 'friend_accepted', jsonb_build_object('from', public.profile_card(uid, r.from_id)));
    perform public.grant_friend_achievement(r.from_id);
    perform public.grant_friend_achievement(uid);
  end if;
end $$;

create or replace function public.friend_cancel(p_id bigint) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := public.require_uid();
begin
  update public.friend_requests set status = 'cancelled', responded_at = now() where id = p_id and from_id = uid and status = 'pending';
  if not found then raise exception 'not_found'; end if;
end $$;

create or replace function public.friend_remove(p_target uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := public.require_uid();
begin
  delete from public.friendships where a = least(uid, p_target) and b = greatest(uid, p_target);
end $$;

create or replace function public.block_user(p_target uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := public.require_uid();
begin
  if p_target = uid then raise exception 'self'; end if;
  insert into public.blocks (blocker, blocked) values (uid, p_target) on conflict do nothing;
  delete from public.friendships where a = least(uid, p_target) and b = greatest(uid, p_target);
  update public.friend_requests set status = 'cancelled', responded_at = now()
    where status = 'pending' and ((from_id = uid and to_id = p_target) or (from_id = p_target and to_id = uid));
end $$;

create or replace function public.unblock_user(p_target uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := public.require_uid();
begin
  delete from public.blocks where blocker = uid and blocked = p_target;
end $$;

create or replace function public.list_friends() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := public.require_uid();
begin
  return coalesce((select jsonb_agg(public.profile_card(f.other, uid) order by public.is_online(f.other) desc)
    from (select case when a = uid then b else a end as other from public.friendships where uid in (a, b)) f), '[]'::jsonb);
end $$;

create or replace function public.list_requests() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := public.require_uid();
begin
  return jsonb_build_object(
    'incoming', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'at', r.created_at, 'user', public.profile_card(r.from_id, uid)) order by r.id desc)
                         from public.friend_requests r where r.to_id = uid and r.status = 'pending'), '[]'::jsonb),
    'outgoing', coalesce((select jsonb_agg(jsonb_build_object('id', r.id, 'at', r.created_at, 'user', public.profile_card(r.to_id, uid)) order by r.id desc)
                         from public.friend_requests r where r.from_id = uid and r.status = 'pending'), '[]'::jsonb),
    'blocked', coalesce((select jsonb_agg(public.profile_card(b.blocked, uid)) from public.blocks b where b.blocker = uid), '[]'::jsonb));
end $$;

create or replace function public.invite_to_room(p_target uuid, p_room uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := public.require_uid(); r public.rooms; priv text;
begin
  select * into r from public.rooms where id = p_room;
  if not found or not (uid = any(r.members)) then raise exception 'not_member'; end if;
  if r.status not in ('waiting', 'playing') then raise exception 'room_closed'; end if;
  if public.blocked_either(uid, p_target) then raise exception 'blocked'; end if;
  select privacy_invites into priv from public.profiles where id = p_target;
  if priv is null then raise exception 'not_found'; end if;
  if priv = 'nobody' or (priv = 'friends' and not public.are_friends(uid, p_target)) then raise exception 'invites_closed'; end if;
  if (select count(*) from public.notifications where kind = 'room_invite' and (data->>'from_id')::uuid = uid and created_at > now() - interval '10 minutes') >= 20 then raise exception 'rate_limited'; end if;
  perform public.notify_user(p_target, 'room_invite', jsonb_build_object('room_id', r.id, 'code', r.code, 'kind', r.kind, 'from_id', uid, 'from', public.profile_card(uid, p_target)));
end $$;

create or replace function public.notif_read(p_ids bigint[] default null) returns void
language plpgsql security definer set search_path = '' as $$
declare uid uuid := public.require_uid();
begin
  update public.notifications set read_at = now() where user_id = uid and read_at is null and (p_ids is null or id = any(p_ids));
end $$;

create or replace function public.my_notifications(p_limit int default 30) returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', n.id, 'kind', n.kind, 'data', n.data, 'at', n.created_at, 'read', n.read_at is not null) order by n.id desc), '[]'::jsonb)
  from (select * from public.notifications where user_id = auth.uid() order by id desc limit least(greatest(p_limit, 1), 100)) n $$;

------------------------------------------------------------------------------------------------
-- chat and reports
------------------------------------------------------------------------------------------------
create or replace function public.quick_phrases() returns text[] language sql immutable set search_path = '' as $$
  select array['هلا والله','يعطيك العافية','ركّز يا خوي','لعبة حلوة','وش ذا؟!','الله يحييك','بالتوفيق','معليش','😂','👏','🔥','😅','🤝','☕'] $$;

create or replace function public.send_chat(p_room uuid, p_body text) returns bigint
language plpgsql security definer set search_path = '' as $$
declare uid uuid := public.require_uid(); r public.rooms; b text := btrim(regexp_replace(coalesce(p_body, ''), '[[:cntrl:]]', ' ', 'g')); mid bigint;
begin
  select * into r from public.rooms where id = p_room;
  if not found or not (uid = any(r.members)) then raise exception 'not_member'; end if;
  if public.is_banned(uid) then raise exception 'banned'; end if;
  if r.chat_mode = 'off' then raise exception 'chat_off'; end if;
  if r.chat_mode = 'quick' and not (b = any(public.quick_phrases())) then raise exception 'quick_only'; end if;
  if char_length(b) < 1 or char_length(b) > 200 then raise exception 'bad_message'; end if;
  if (select count(*) from public.chat_messages where user_id = uid and created_at > now() - interval '10 seconds') >= 4 then raise exception 'slow_down'; end if;
  if (select count(*) from public.chat_messages where user_id = uid and created_at > now() - interval '1 minute') >= 20 then raise exception 'slow_down'; end if;
  insert into public.chat_messages (room_id, user_id, body) values (p_room, uid, b) returning id into mid;
  return mid;
end $$;

create or replace function public.report_submit(p_kind text, p_target uuid, p_ref text, p_reason text, p_details text default '') returns bigint
language plpgsql security definer set search_path = '' as $$
declare uid uuid := public.require_uid(); rid bigint; m public.chat_messages;
begin
  if p_reason not in ('abuse','cheating','spam','inappropriate_name','leaving','other') then raise exception 'bad_reason'; end if;
  if (select count(*) from public.reports where reporter = uid and created_at > now() - interval '1 day') >= 15 then raise exception 'rate_limited'; end if;
  if p_kind = 'message' then
    select * into m from public.chat_messages where id = p_ref::bigint;
    if not found or not exists (select 1 from public.rooms r where r.id = m.room_id and uid = any(r.members)) then raise exception 'not_found'; end if;
    p_target := m.user_id;
  elsif p_kind = 'match' then
    if not exists (select 1 from public.matches where id = p_ref::uuid and uid = any(player_ids)) then raise exception 'not_found'; end if;
  elsif p_kind <> 'user' then raise exception 'bad_kind'; end if;
  if p_target = uid then raise exception 'self'; end if;
  insert into public.reports (reporter, kind, target_user, ref_id, reason, details) values (uid, p_kind, p_target, p_ref, p_reason, left(coalesce(p_details, ''), 500)) returning id into rid;
  return rid;
end $$;

------------------------------------------------------------------------------------------------
-- leaderboards and match details
------------------------------------------------------------------------------------------------
create or replace function public.leaderboard(p_scope text default 'global', p_limit int default 50) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v uuid := auth.uid(); lim int := least(greatest(p_limit, 1), 100);
begin
  if p_scope = 'season' then
    return coalesce((select jsonb_agg(x) from (select jsonb_build_object('user', public.profile_card(st.user_id, v), 'rating', st.rating, 'games', st.games, 'wins', st.wins) x
      from public.season_stats st join public.seasons s on s.id = st.season_id and s.active where st.games > 0 order by st.rating desc, st.wins desc limit lim) t), '[]'::jsonb);
  elsif p_scope = 'friends' then
    return coalesce((select jsonb_agg(x) from (select jsonb_build_object('user', public.profile_card(p.id, v), 'rating', p.rating, 'games', p.games, 'wins', p.wins) x
      from public.profiles p where p.id = v or public.are_friends(p.id, v) order by p.rating desc, p.wins desc limit lim) t), '[]'::jsonb);
  end if;
  return coalesce((select jsonb_agg(x) from (select jsonb_build_object('user', public.profile_card(p.id, v), 'rating', p.rating, 'games', p.games, 'wins', p.wins) x
    from public.profiles p where p.ranked_games > 0 order by p.rating desc, p.wins desc limit lim) t), '[]'::jsonb);
end $$;

create or replace function public.match_detail(p_match uuid) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare v uuid := public.require_uid(); m public.matches; staff boolean := public.is_staff(v);
begin
  select * into m from public.matches where id = p_match;
  if not found or not (v = any(m.player_ids) or staff) then raise exception 'not_found'; end if;
  return jsonb_build_object('id', m.id, 'ranked', m.ranked, 'status', m.status, 'rules', m.rules, 'players', m.players,
    'score0', m.score0, 'score1', m.score1, 'winner_team', m.winner_team, 'rounds', m.rounds, 'started_at', m.started_at, 'ended_at', m.ended_at,
    'results', (select jsonb_agg(jsonb_build_object('user_id', mp.user_id, 'seat', mp.seat, 'result', mp.result, 'abandoned', mp.abandoned,
                  'rating_before', mp.rating_before, 'rating_after', mp.rating_after, 'xp', mp.xp_gained)) from public.match_players mp where mp.match_id = m.id),
    'events', case when m.status <> 'playing' then (select jsonb_agg(jsonb_build_object('seq', e.seq, 'kind', e.kind, 'data', e.data) order by e.seq) from public.match_events e where e.match_id = m.id) end);
end $$;

------------------------------------------------------------------------------------------------
-- progression: achievements, challenges, cosmetics
------------------------------------------------------------------------------------------------
create or replace function public.unlock_achievement(p_uid uuid, p_code text) returns void
language plpgsql security definer set search_path = '' as $$
declare a public.achievements; n int;
begin
  insert into public.user_achievements (user_id, code) values (p_uid, p_code) on conflict do nothing;
  get diagnostics n = row_count;
  if n = 0 then return; end if;
  select * into a from public.achievements where code = p_code;
  update public.profiles set xp = xp + a.xp, level = public.level_for(xp + a.xp) where id = p_uid;
  if a.reward_cosmetic is not null then insert into public.user_cosmetics (user_id, code) values (p_uid, a.reward_cosmetic) on conflict do nothing; end if;
  perform public.notify_user(p_uid, 'achievement', jsonb_build_object('code', a.code, 'name', a.name, 'icon', a.icon, 'xp', a.xp));
end $$;

create or replace function public.grant_friend_achievement(p_uid uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.friendships where p_uid in (a, b)) >= 5 then perform public.unlock_achievement(p_uid, 'friends_5'); end if;
end $$;

create or replace function public.sync_level_cosmetics(p_uid uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare lvl int;
begin
  select level into lvl from public.profiles where id = p_uid;
  insert into public.user_cosmetics (user_id, code)
    select p_uid, code from public.cosmetics where unlock like 'level:%' and split_part(unlock, ':', 2)::int <= lvl on conflict do nothing;
end $$;

create or replace function public.bump_challenges(p_uid uuid, p_metrics jsonb) returns void
language plpgsql security definer set search_path = '' as $$
declare c public.challenges; key text; inc int; uc public.user_challenges;
begin
  for c in select * from public.challenges where active loop
    inc := coalesce((p_metrics->>c.metric)::int, 0);
    if inc <= 0 then continue; end if;
    key := case c.period when 'daily' then to_char(now() at time zone 'Asia/Riyadh', 'YYYY-MM-DD') else to_char(now() at time zone 'Asia/Riyadh', 'IYYY-"W"IW') end;
    insert into public.user_challenges (user_id, challenge_id, period_key, progress) values (p_uid, c.id, key, 0) on conflict do nothing;
    select * into uc from public.user_challenges where user_id = p_uid and challenge_id = c.id and period_key = key for update;
    if uc.completed_at is not null then continue; end if;
    update public.user_challenges set progress = least(progress + inc, c.target),
      completed_at = case when progress + inc >= c.target then now() end
      where user_id = p_uid and challenge_id = c.id and period_key = key;
    if uc.progress + inc >= c.target then
      update public.profiles set xp = xp + c.reward_xp, level = public.level_for(xp + c.reward_xp) where id = p_uid;
      if c.reward_cosmetic is not null then insert into public.user_cosmetics (user_id, code) values (p_uid, c.reward_cosmetic) on conflict do nothing; end if;
      perform public.notify_user(p_uid, 'challenge', jsonb_build_object('title', c.title, 'xp', c.reward_xp));
    end if;
  end loop;
end $$;

create or replace function public.my_progress() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare uid uuid := public.require_uid(); dk text := to_char(now() at time zone 'Asia/Riyadh', 'YYYY-MM-DD'); wk text := to_char(now() at time zone 'Asia/Riyadh', 'IYYY-"W"IW');
begin
  return jsonb_build_object(
    'challenges', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'title', c.title, 'period', c.period, 'target', c.target, 'reward_xp', c.reward_xp,
        'reward', c.reward_cosmetic, 'progress', coalesce(uc.progress, 0), 'done', uc.completed_at is not null) order by c.period, c.id)
      from public.challenges c left join public.user_challenges uc on uc.challenge_id = c.id and uc.user_id = uid
        and uc.period_key = case c.period when 'daily' then dk else wk end where c.active), '[]'::jsonb),
    'achievements', coalesce((select jsonb_agg(jsonb_build_object('code', a.code, 'name', a.name, 'description', a.description, 'icon', a.icon, 'xp', a.xp,
        'unlocked', ua.unlocked_at) order by a.sort) from public.achievements a left join public.user_achievements ua on ua.code = a.code and ua.user_id = uid), '[]'::jsonb),
    'cosmetics', coalesce((select jsonb_agg(jsonb_build_object('code', c.code, 'kind', c.kind, 'name', c.name, 'unlock', c.unlock, 'owned', uc.user_id is not null) order by c.kind, c.sort)
      from public.cosmetics c left join public.user_cosmetics uc on uc.code = c.code and uc.user_id = uid), '[]'::jsonb));
end $$;

------------------------------------------------------------------------------------------------
-- game server support (called by the `api` Edge Function with the service role only)
------------------------------------------------------------------------------------------------
create or replace function public.save_room(p_id uuid, p_version int, p_fields jsonb, p_g jsonb, p_meta jsonb, p_hands jsonb, p_match uuid, p_events jsonb)
returns boolean language plpgsql security definer set search_path = '' as $$
declare n int;
begin
  update public.rooms set
    state   = case when p_fields ? 'state' then p_fields->'state' else state end,
    seats   = case when p_fields ? 'seats' then p_fields->'seats' else seats end,
    members = case when p_fields ? 'members' then array(select x::uuid from jsonb_array_elements_text(p_fields->'members') x) else members end,
    status  = coalesce(p_fields->>'status', status),
    owner   = case when p_fields ? 'owner' then nullif(p_fields->>'owner', '')::uuid else owner end,
    rules   = case when p_fields ? 'rules' then p_fields->'rules' else rules end,
    chat_mode = coalesce(p_fields->>'chat_mode', chat_mode),
    match_id = case when p_fields ? 'match_id' then nullif(p_fields->>'match_id', '')::uuid else match_id end,
    version = version + 1, updated_at = now()
  where id = p_id and version = p_version;
  get diagnostics n = row_count;
  if n = 0 then return false; end if;
  if p_g is not null or p_meta is not null then
    insert into public.room_secrets (room_id, g, meta) values (p_id, p_g, coalesce(p_meta, '{}'::jsonb))
    on conflict (room_id) do update set g = case when p_g is null then public.room_secrets.g else excluded.g end,
                                        meta = case when p_meta is null then public.room_secrets.meta else excluded.meta end;
  end if;
  if p_hands is not null and jsonb_array_length(p_hands) > 0 then
    insert into public.room_hands (room_id, seat, user_id, cards)
    select p_id, (h->>'seat')::int, nullif(h->>'user_id', '')::uuid, array(select jsonb_array_elements_text(h->'cards')) from jsonb_array_elements(p_hands) h
    on conflict (room_id, seat) do update set user_id = excluded.user_id, cards = excluded.cards;
  end if;
  if p_match is not null and p_events is not null and jsonb_array_length(p_events) > 0 then
    insert into public.match_events (match_id, seq, kind, data)
    select p_match, (e->>'seq')::int, e->>'kind', coalesce(e->'data', '[]'::jsonb) from jsonb_array_elements(p_events) e
    on conflict (match_id, seq) do nothing;
  end if;
  return true;
end $$;

/** Records a finished match exactly once: results, ratings, stats, XP, achievements, challenges, notifications. */
create or replace function public.finalize_match(p_match uuid, p_result jsonb) returns boolean
language plpgsql security definer set search_path = '' as $$
declare m public.matches; pl jsonb; uid uuid; tm int; won boolean; ab boolean; k int := 32; ranked boolean;
  avg0 numeric; avg1 numeric; expct numeric; delta int; before int; xpg int; season int; teammate_left boolean; streak int; prof public.profiles;
  w int := (p_result->>'winner_team')::int; kab jsonb := coalesce(p_result->'kab', '[0,0]'::jsonb); friends_in boolean;
begin
  select * into m from public.matches where id = p_match for update;
  if not found or m.recorded then return false; end if;
  ranked := m.ranked;
  select id into season from public.seasons where active;
  select avg(p.rating) into avg0 from public.profiles p where p.id in (select (x->>'uid')::uuid from jsonb_array_elements(p_result->'players') x where (x->>'team')::int = 0);
  select avg(p.rating) into avg1 from public.profiles p where p.id in (select (x->>'uid')::uuid from jsonb_array_elements(p_result->'players') x where (x->>'team')::int = 1);
  update public.matches set status = coalesce(p_result->>'status', 'finished'), score0 = (p_result->>'score0')::int, score1 = (p_result->>'score1')::int,
    winner_team = w, rounds = coalesce(p_result->'rounds', '[]'::jsonb), ended_at = now(), recorded = true where id = p_match;
  for pl in select * from jsonb_array_elements(p_result->'players') loop
    uid := (pl->>'uid')::uuid; tm := (pl->>'team')::int; ab := coalesce((pl->>'abandoned')::boolean, false);
    won := coalesce(w = tm, false) and not ab;
    select * into prof from public.profiles where id = uid;
    if not found then continue; end if;
    before := prof.rating;
    teammate_left := exists (select 1 from jsonb_array_elements(p_result->'players') y where (y->>'team')::int = tm and (y->>'uid')::uuid <> uid and coalesce((y->>'abandoned')::boolean, false));
    delta := 0;
    if ranked then
      expct := 1 / (1 + power(10, ((case when tm = 0 then avg1 else avg0 end) - (case when tm = 0 then avg0 else avg1 end)) / 400.0));
      delta := round(k * ((case when won then 1 else 0 end) - expct));
      if ab then delta := least(delta, 0) - 15;
      elsif not won and teammate_left then delta := delta / 2; end if;
    end if;
    xpg := case when ab then 0 else 30 + (case when won then 20 else 0 end) + 10 * coalesce((kab->>tm)::int, 0) end;
    streak := case when won then prof.cur_streak + 1 else 0 end;
    update public.profiles set
      games = games + 1, wins = wins + (case when won then 1 else 0 end), losses = losses + (case when won then 0 else 1 end),
      kaboots = kaboots + coalesce((kab->>tm)::int, 0),
      sun_rounds = sun_rounds + coalesce((pl->>'sun_rounds')::int, 0), sun_won = sun_won + coalesce((pl->>'sun_won')::int, 0),
      hokm_rounds = hokm_rounds + coalesce((pl->>'hokm_rounds')::int, 0), hokm_won = hokm_won + coalesce((pl->>'hokm_won')::int, 0),
      cur_streak = streak, best_streak = greatest(best_streak, streak),
      ranked_games = ranked_games + (case when ranked then 1 else 0 end),
      rating = greatest(0, rating + delta), xp = xp + xpg, level = public.level_for(xp + xpg)
      where id = uid returning * into prof;
    insert into public.match_players (match_id, user_id, seat, team, result, abandoned, rating_before, rating_after, xp_gained)
      values (p_match, uid, (pl->>'seat')::int, tm, case when won then 'win' else 'loss' end, ab, before, prof.rating, xpg)
      on conflict do nothing;
    if ranked and season is not null then
      insert into public.season_stats (season_id, user_id, rating, games, wins) values (season, uid, 1000 + delta, 1, case when won then 1 else 0 end)
      on conflict (season_id, user_id) do update set rating = greatest(0, public.season_stats.rating + delta), games = public.season_stats.games + 1,
        wins = public.season_stats.wins + (case when won then 1 else 0 end);
    end if;
    -- achievements from verified stats
    if prof.games >= 1 then perform public.unlock_achievement(uid, 'first_match'); end if;
    if prof.wins >= 1 then perform public.unlock_achievement(uid, 'first_win'); end if;
    if prof.wins >= 10 then perform public.unlock_achievement(uid, 'wins_10'); end if;
    if prof.wins >= 50 then perform public.unlock_achievement(uid, 'wins_50'); end if;
    if prof.games >= 100 then perform public.unlock_achievement(uid, 'games_100'); end if;
    if prof.kaboots >= 1 then perform public.unlock_achievement(uid, 'kaboot_1'); end if;
    if prof.best_streak >= 5 then perform public.unlock_achievement(uid, 'streak_5'); end if;
    if prof.sun_won >= 10 then perform public.unlock_achievement(uid, 'sun_10'); end if;
    if prof.hokm_won >= 10 then perform public.unlock_achievement(uid, 'hokm_10'); end if;
    if prof.ranked_games >= 10 then perform public.unlock_achievement(uid, 'ranked_10'); end if;
    if won and coalesce((p_result->>'gahwa')::boolean, false) then perform public.unlock_achievement(uid, 'gahwa'); end if;
    friends_in := exists (select 1 from jsonb_array_elements(p_result->'players') y where (y->>'uid')::uuid <> uid and public.are_friends(uid, (y->>'uid')::uuid));
    if not ab then
      perform public.bump_challenges(uid, jsonb_build_object('matches', 1, 'wins', case when won then 1 else 0 end, 'kaboots', coalesce((kab->>tm)::int, 0),
        'sun_bought', coalesce((pl->>'sun_rounds')::int, 0), 'ranked', case when ranked then 1 else 0 end, 'friend_matches', case when friends_in then 1 else 0 end));
    end if;
    perform public.sync_level_cosmetics(uid);
    perform public.notify_user(uid, 'match_result', jsonb_build_object('match_id', p_match, 'won', won, 'abandoned', ab, 'rating_delta', delta, 'xp', xpg,
      'us', case when tm = 0 then (p_result->>'score0')::int else (p_result->>'score1')::int end,
      'them', case when tm = 0 then (p_result->>'score1')::int else (p_result->>'score0')::int end, 'ranked', ranked));
  end loop;
  return true;
end $$;

/** Atomically takes 4 compatible players out of the queue. The window widens the longer the oldest player waits. */
create or replace function public.queue_try_match(p_mode text) returns uuid[]
language plpgsql security definer set search_path = '' as $$
declare first public.queue; win int; picked uuid[];
begin
  select * into first from public.queue where mode = p_mode order by created_at limit 1 for update skip locked;
  if not found then return null; end if;
  win := case when p_mode = 'friendly' then 100000 else 150 + (extract(epoch from now() - first.created_at)::int / 15) * 50 end;
  select array_agg(user_id) into picked from (
    select user_id from public.queue where mode = p_mode and user_id <> first.user_id and abs(rating - first.rating) <= win
    order by created_at limit 3 for update skip locked) t;
  if picked is null or array_length(picked, 1) < 3 then return null; end if;
  picked := array_prepend(first.user_id, picked);
  delete from public.queue where user_id = any(picked);
  return picked;
end $$;

------------------------------------------------------------------------------------------------
-- administration (role checked in every function, every action audited)
------------------------------------------------------------------------------------------------
create or replace function public.audit(p_action text, p_target text, p_details jsonb) returns void
language sql security definer set search_path = '' as $$
  insert into public.audit_log (actor, action, target, details) values (auth.uid(), p_action, p_target, coalesce(p_details, '{}'::jsonb)) $$;

create or replace function public.require_staff(p_min text default 'moderator') returns uuid
language plpgsql stable security definer set search_path = '' as $$
declare v uuid := public.require_uid();
begin
  if not public.is_staff(v, p_min) then raise exception 'forbidden'; end if;
  return v;
end $$;

create or replace function public.admin_overview() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.require_staff();
  return jsonb_build_object(
    'users', (select count(*) from auth.users),
    'profiles', (select count(*) from public.profiles),
    'online', (select count(*) from public.account_private where last_seen > now() - interval '2 minutes'),
    'rooms_waiting', (select count(*) from public.rooms where status = 'waiting'),
    'rooms_playing', (select count(*) from public.rooms where status = 'playing'),
    'matches_today', (select count(*) from public.matches where started_at > now() - interval '1 day'),
    'matches_total', (select count(*) from public.matches where status = 'finished'),
    'queue', (select count(*) from public.queue),
    'open_reports', (select count(*) from public.reports where status = 'open'),
    'errors_24h', (select count(*) from public.server_errors where at > now() - interval '1 day'),
    'signups_7d', (select count(*) from auth.users where created_at > now() - interval '7 days'));
end $$;

create or replace function public.admin_players(p_q text default '') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.require_staff();
  return coalesce((select jsonb_agg(x) from (select jsonb_build_object('id', p.id, 'username', p.username, 'display_name', p.display_name, 'player_no', p.player_no,
      'rating', p.rating, 'games', p.games, 'joined', p.created_at, 'last_seen', a.last_seen, 'ban_until', a.ban_until, 'ban_permanent', a.ban_permanent, 'ban_reason', a.ban_reason,
      'role', (select role from public.admin_roles r where r.user_id = p.id),
      'reports', (select count(*) from public.reports rp where rp.target_user = p.id)) x
    from public.profiles p left join public.account_private a on a.user_id = p.id
    where coalesce(p_q, '') = '' or p.username ilike '%' || p_q || '%' or p.player_no::text = p_q
    order by p.created_at desc limit 100) t), '[]'::jsonb);
end $$;

create or replace function public.admin_ban(p_user uuid, p_hours int, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare v uuid := public.require_staff();
begin
  if char_length(btrim(coalesce(p_reason, ''))) < 3 then raise exception 'reason_required'; end if;
  if public.is_staff(p_user) and not public.is_staff(v, 'owner') then raise exception 'forbidden'; end if;
  if p_hours is null and not public.is_staff(v, 'admin') then raise exception 'forbidden'; end if;
  if p_hours is not null and p_hours > 72 and not public.is_staff(v, 'admin') then raise exception 'forbidden'; end if;
  insert into public.account_private (user_id) values (p_user) on conflict do nothing;
  update public.account_private set ban_permanent = p_hours is null, ban_until = case when p_hours is null then null else now() + make_interval(hours => p_hours) end,
    ban_reason = p_reason where user_id = p_user;
  delete from public.queue where user_id = p_user;
  perform public.audit('ban', p_user::text, jsonb_build_object('hours', p_hours, 'reason', p_reason));
end $$;

create or replace function public.admin_unban(p_user uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.require_staff();
  update public.account_private set ban_permanent = false, ban_until = null, ban_reason = null where user_id = p_user;
  perform public.audit('unban', p_user::text, '{}'::jsonb);
end $$;

create or replace function public.admin_reports(p_status text default 'open') returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.require_staff();
  return coalesce((select jsonb_agg(x) from (select jsonb_build_object('id', r.id, 'kind', r.kind, 'reason', r.reason, 'details', r.details, 'ref_id', r.ref_id,
      'status', r.status, 'at', r.created_at, 'resolution', r.resolution,
      'reporter', (select username from public.profiles where id = r.reporter), 'target_id', r.target_user,
      'target', (select username from public.profiles where id = r.target_user),
      'message', case when r.kind = 'message' then (select body from public.chat_messages where id = r.ref_id::bigint) end) x
    from public.reports r where p_status = 'all' or r.status = p_status order by r.id desc limit 200) t), '[]'::jsonb);
end $$;

create or replace function public.admin_resolve_report(p_id bigint, p_status text, p_resolution text, p_hide_message boolean default false) returns void
language plpgsql security definer set search_path = '' as $$
declare v uuid := public.require_staff(); r public.reports;
begin
  if p_status not in ('resolved', 'dismissed') then raise exception 'bad_status'; end if;
  update public.reports set status = p_status, resolution = p_resolution, resolved_by = v, resolved_at = now() where id = p_id returning * into r;
  if not found then raise exception 'not_found'; end if;
  if p_hide_message and r.kind = 'message' then update public.chat_messages set hidden = true where id = r.ref_id::bigint; end if;
  perform public.audit('resolve_report', p_id::text, jsonb_build_object('status', p_status, 'resolution', p_resolution, 'hidden', p_hide_message));
end $$;

create or replace function public.admin_rooms() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.require_staff();
  return coalesce((select jsonb_agg(x) from (select jsonb_build_object('id', r.id, 'code', r.code, 'kind', r.kind, 'status', r.status, 'updated_at', r.updated_at,
      'stuck', r.updated_at < now() - interval '20 minutes', 'players', (select count(*) from jsonb_array_elements(r.seats) s where s <> 'null'::jsonb), 'match_id', r.match_id) x
    from public.rooms r where r.status in ('waiting', 'playing') order by r.updated_at limit 200) t), '[]'::jsonb);
end $$;

create or replace function public.admin_close_room(p_room uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare r public.rooms;
begin
  perform public.require_staff();
  update public.rooms set status = 'closed', version = version + 1, updated_at = now() where id = p_room returning * into r;
  if not found then raise exception 'not_found'; end if;
  update public.matches set status = 'abandoned', ended_at = now(), recorded = true where id = r.match_id and status = 'playing';
  perform public.audit('close_room', p_room::text, jsonb_build_object('reason', p_reason));
end $$;

create or replace function public.admin_season_start(p_name text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.require_staff('admin');
  update public.seasons set active = false, ends_at = now() where active;
  insert into public.seasons (name, active) values (p_name, true);
  perform public.audit('season_start', p_name, '{}'::jsonb);
end $$;

create or replace function public.admin_challenge_toggle(p_id int, p_active boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.require_staff('admin');
  update public.challenges set active = p_active where id = p_id;
  perform public.audit('challenge_toggle', p_id::text, jsonb_build_object('active', p_active));
end $$;

create or replace function public.admin_set_role(p_user uuid, p_role text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform public.require_staff('owner');
  if p_role is null then delete from public.admin_roles where user_id = p_user and role <> 'owner';
  elsif p_role in ('admin', 'moderator') then
    insert into public.admin_roles (user_id, role, granted_by) values (p_user, p_role, auth.uid()) on conflict (user_id) do update set role = excluded.role where public.admin_roles.role <> 'owner';
  else raise exception 'bad_role'; end if;
  perform public.audit('set_role', p_user::text, jsonb_build_object('role', p_role));
end $$;

create or replace function public.admin_logs() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  perform public.require_staff();
  return jsonb_build_object(
    'errors', coalesce((select jsonb_agg(jsonb_build_object('at', e.at, 'source', e.source, 'message', e.message, 'context', e.context) order by e.id desc)
                        from (select * from public.server_errors order by id desc limit 100) e), '[]'::jsonb),
    'audit', coalesce((select jsonb_agg(jsonb_build_object('at', a.created_at, 'actor', (select username from public.profiles where id = a.actor), 'action', a.action, 'target', a.target, 'details', a.details) order by a.id desc)
                       from (select * from public.audit_log order by id desc limit 100) a), '[]'::jsonb),
    'seasons', coalesce((select jsonb_agg(to_jsonb(s) order by s.id desc) from public.seasons s), '[]'::jsonb),
    'challenges', coalesce((select jsonb_agg(to_jsonb(c) order by c.id) from public.challenges c), '[]'::jsonb));
end $$;

------------------------------------------------------------------------------------------------
-- permissions: service-only functions are not callable by users
------------------------------------------------------------------------------------------------
revoke execute on function public.save_room(uuid, int, jsonb, jsonb, jsonb, jsonb, uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.finalize_match(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.queue_try_match(text) from public, anon, authenticated;
revoke execute on function public.notify_user(uuid, text, jsonb) from public, anon, authenticated;
revoke execute on function public.unlock_achievement(uuid, text) from public, anon, authenticated;
revoke execute on function public.bump_challenges(uuid, jsonb) from public, anon, authenticated;
revoke execute on function public.sync_level_cosmetics(uuid) from public, anon, authenticated;
revoke execute on function public.grant_friend_achievement(uuid) from public, anon, authenticated;
revoke execute on function public.profiles_guard() from public, anon, authenticated;

------------------------------------------------------------------------------------------------
-- catalogue seed (real definitions, not player data)
------------------------------------------------------------------------------------------------
insert into public.cosmetics (code, kind, name, unlock, sort) values
  ('classic', 'table', 'أخضر الديوانية', 'default', 1), ('night', 'table', 'ليل الرياض', 'level:3', 2), ('maroon', 'table', 'عنّابي', 'achievement:wins_10', 3),
  ('royal', 'table', 'أزرق ملكي', 'challenge', 4), ('sand', 'table', 'رمل النفود', 'level:8', 5),
  ('sadu', 'back', 'سدو أحمر', 'default', 1), ('gold', 'back', 'ذهبي', 'level:5', 2), ('navy', 'back', 'كحلي', 'achievement:kaboot_1', 3), ('palm', 'back', 'نخيل', 'challenge', 4),
  ('none', 'frame', 'بدون إطار', 'default', 1), ('bronze', 'frame', 'برونزي', 'level:2', 2), ('silver', 'frame', 'فضي', 'level:6', 3), ('goldf', 'frame', 'ذهبي', 'level:10', 4),
  ('champion', 'frame', 'إطار البطل', 'achievement:streak_5', 5)
on conflict (code) do nothing;
insert into public.achievements (code, name, description, icon, xp, reward_cosmetic, sort) values
  ('first_match', 'أول صكة', 'أكمل أول مباراة لك.', '🎴', 20, null, 1),
  ('first_win', 'أول فوز', 'افز بمباراة.', '🏅', 30, null, 2),
  ('wins_10', 'لاعب ثابت', 'افز بعشر مباريات.', '🥈', 80, 'maroon', 3),
  ('wins_50', 'شيخ الديوانية', 'افز بخمسين مباراة.', '🥇', 250, null, 4),
  ('games_100', 'المية', 'أكمل مئة مباراة.', '💯', 200, null, 5),
  ('kaboot_1', 'كبّوت', 'اكسب كل الأكلات في توزيعة.', '🧹', 60, 'navy', 6),
  ('streak_5', 'سلسلة نارية', 'خمس انتصارات متتالية.', '🔥', 120, 'champion', 7),
  ('sun_10', 'ملك الصن', 'اكسب عشر توزيعات صن اشتريتها.', '☀️', 100, null, 8),
  ('hokm_10', 'أبو الحكم', 'اكسب عشر توزيعات حكم اشتريتها.', '♠️', 100, null, 9),
  ('ranked_10', 'منافس', 'أكمل عشر مباريات مصنّفة.', '⚔️', 100, null, 10),
  ('gahwa', 'قهوجي', 'افز بمباراة حُسمت بالقهوة.', '☕', 150, null, 11),
  ('friends_5', 'ربع الديوانية', 'كوّن خمس صداقات.', '🤝', 50, null, 12)
on conflict (code) do nothing;
insert into public.challenges (code, period, title, metric, target, reward_xp, reward_cosmetic) values
  ('d_play2', 'daily', 'العب مباراتين', 'matches', 2, 40, null),
  ('d_win1', 'daily', 'افز بمباراة', 'wins', 1, 50, null),
  ('d_sun3', 'daily', 'اشترِ صن ٣ مرات', 'sun_bought', 3, 40, 'palm'),
  ('w_win5', 'weekly', 'افز بخمس مباريات', 'wins', 5, 200, 'royal'),
  ('w_kaboot', 'weekly', 'سوّ كبوت', 'kaboots', 1, 150, null),
  ('w_friends3', 'weekly', 'العب ٣ مباريات مع أصدقائك', 'friend_matches', 3, 150, null),
  ('w_ranked5', 'weekly', 'أكمل ٥ مباريات مصنّفة', 'ranked', 5, 200, null)
on conflict (code) do nothing;
insert into public.seasons (name, active) select 'الموسم الأول', true where not exists (select 1 from public.seasons);
