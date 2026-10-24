-- Production end-to-end test: four real accounts play a full match against the live "api" Edge Function.
-- Runs INSIDE the project's database (SQL editor), using the `http` and `pg_net` extensions, because it drives
-- the public HTTPS API exactly as four browsers would. Each step is a separate statement: run them in order,
-- repeating step 6 until it returns "done": true. Test users live in schema e2e and use @example.com addresses.
-- Cleanup: delete each test account with the api action delete_account (confirm = username) — see docs/TESTING.md.
--
-- Replace PROJECT_URL and PUBLISHABLE_KEY below (both are public values, not secrets).

create extension if not exists http with schema extensions;
create schema if not exists e2e;
revoke all on schema e2e from public, anon, authenticated;
create table if not exists e2e.log (id bigserial primary key, at timestamptz default now(), step text, ok boolean, info jsonb);
create table if not exists e2e.users (n int primary key, id uuid, email text, token text, token_at timestamptz);
create table if not exists e2e.kv (k text primary key, v jsonb);

create or replace function e2e.req(p_method text, p_path text, p_token text, p_body jsonb) returns jsonb language plpgsql as $f$
declare r extensions.http_response; key text := 'PUBLISHABLE_KEY';
begin
  r := extensions.http((p_method, 'PROJECT_URL' || p_path,
     array[extensions.http_header('apikey', key), extensions.http_header('Authorization', 'Bearer ' || coalesce(p_token, key))],
     'application/json', case when p_body is null then null else p_body::text end)::extensions.http_request);
  return jsonb_build_object('status', r.status, 'body', case when r.content ~ '^\s*[\[{"]' then r.content::jsonb else to_jsonb(r.content) end);
end $f$;

-- Signs in with the password grant and caches the access token for 40 minutes.
create or replace function e2e.tok(p_n int) returns text language plpgsql as $f$
declare t text; at timestamptz; em text;
begin
  select token, token_at, email into t, at, em from e2e.users where n = p_n;
  if t is null or at is null or at < now() - interval '40 minutes' then
    t := e2e.req('POST', '/auth/v1/token?grant_type=password', null, jsonb_build_object('email', em, 'password', 'E2e-pass-9481'))->'body'->>'access_token';
    update e2e.users set token = t, token_at = now() where n = p_n;
  end if;
  return t;
end $f$;
create or replace function e2e.uid(p_n int) returns uuid language sql as $f$ select id from e2e.users where n = p_n $f$;
create or replace function e2e.api(p_n int, p_action text, p_body jsonb default '{}') returns jsonb language sql as $f$
  select e2e.req('POST', '/functions/v1/api', e2e.tok(p_n), p_body || jsonb_build_object('action', p_action)) $f$;
create or replace function e2e.rpc(p_n int, p_fn text, p_body jsonb default '{}') returns jsonb language sql as $f$
  select e2e.req('POST', '/rest/v1/rpc/' || p_fn, e2e.tok(p_n), p_body) $f$;
create or replace function e2e.get(p_n int, p_path text) returns jsonb language sql as $f$
  select e2e.req('GET', '/rest/v1/' || p_path, e2e.tok(p_n), null) $f$;
create or replace function e2e.note(p_step text, p_ok boolean, p_info jsonb default null) returns void language sql as $f$
  insert into e2e.log (step, ok, info) values (p_step, p_ok, p_info) $f$;
create or replace function e2e.bump(p_key text, p_by int default 1) returns void language sql as $f$
  insert into e2e.kv values ('stats', jsonb_build_object(p_key, p_by)) on conflict (k) do update
  set v = e2e.kv.v || jsonb_build_object(p_key, coalesce((e2e.kv.v->>p_key)::int, 0) + p_by) $f$;
create or replace function e2e.nseat(p_seat int) returns int language sql as $f$
  select n from e2e.users where id = (select (seats->p_seat->>'uid')::uuid from public.rooms where id = (select (kv.v->>'id')::uuid from e2e.kv kv where kv.k='room')) $f$;
-- Heartbeat for all four players (the server treats a player without one for 3 minutes as gone).
create or replace function e2e.beat() returns void language plpgsql as $f$
declare i int;
begin
  if coalesce((select (kv.v->>'at')::timestamptz from e2e.kv kv where kv.k='beat'), 'epoch') > now() - interval '20 seconds' then return; end if;
  for i in 1..4 loop perform e2e.rpc(i, 'touch'); end loop;
  insert into e2e.kv values ('beat', jsonb_build_object('at', now())) on conflict (k) do update set v = excluded.v;
end $f$;

-- Step 1: four confirmed test accounts (created directly because the hosted mailer cannot confirm test inboxes).
create or replace function e2e.make_users() returns int language plpgsql as $f$
declare i int; u uuid; em text;
begin
  for i in 1..4 loop
    u := gen_random_uuid(); em := 'e2e' || i || '.' || to_char(now(), 'MMDDHH24MI') || '@example.com';
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
      confirmation_token, recovery_token, email_change_token_new, email_change, email_change_token_current, phone_change, phone_change_token, reauthentication_token)
    values ('00000000-0000-0000-0000-000000000000', u, 'authenticated', 'authenticated', em, extensions.crypt('E2e-pass-9481', extensions.gen_salt('bf')), now(),
      '{"provider":"email","providers":["email"],"e2e":true}', '{}', now(), now(), '', '', '', '', '', '', '', '');
    insert into auth.identities (id, user_id, provider_id, identity_data, provider, created_at, updated_at, last_sign_in_at)
    values (gen_random_uuid(), u, u::text, jsonb_build_object('sub', u::text, 'email', em, 'email_verified', true), 'email', now(), now(), now());
    insert into e2e.users (n, id, email) values (i, u, em) on conflict (n) do update set id = excluded.id, email = excluded.email, token = null, token_at = null;
  end loop;
  return 4;
end $f$;

-- Step 3: social graph, privacy and permission checks.
create or replace function e2e.social() returns jsonb language plpgsql as $f$
declare r jsonb; rid bigint;
begin
  r := e2e.rpc(1, 'friend_send', jsonb_build_object('p_target', e2e.uid(2)));       perform e2e.note('friend_send 1→2', r->>'status' = '200', r);
  r := e2e.rpc(2, 'list_requests');
  rid := (select (x->>'id')::bigint from jsonb_array_elements(r->'body'->'incoming') x limit 1);
  perform e2e.note('2 sees incoming request', rid is not null, r->'body');
  r := e2e.rpc(2, 'friend_respond', jsonb_build_object('p_id', rid, 'p_accept', true)); perform e2e.note('accept request', r->>'status' in ('200','204'), r);
  r := e2e.rpc(1, 'list_friends'); perform e2e.note('1 lists 2 as friend', r->'body' @> jsonb_build_array(jsonb_build_object('id', e2e.uid(2))), null);
  r := e2e.rpc(2, 'my_notifications'); perform e2e.note('friend_request notification stored', exists (select 1 from jsonb_array_elements(r->'body') x where x->>'kind' = 'friend_request'), null);
  r := e2e.rpc(1, 'friend_send', jsonb_build_object('p_target', e2e.uid(2))); perform e2e.note('duplicate request rejected', r->>'status' <> '200', r);
  r := e2e.api(3, 'block', jsonb_build_object('target', e2e.uid(4)));             perform e2e.note('3 blocks 4', r->>'status' = '200', r);
  r := e2e.rpc(4, 'friend_send', jsonb_build_object('p_target', e2e.uid(3)));     perform e2e.note('blocked user cannot send request', r->>'status' <> '200', r);
  r := e2e.api(3, 'unblock', jsonb_build_object('target', e2e.uid(4)));           perform e2e.note('3 unblocks 4', r->>'status' = '200', r);
  r := e2e.req('PATCH', '/rest/v1/profiles?id=eq.' || e2e.uid(1), e2e.tok(1), jsonb_build_object('bio', 'نبذة اختبار'));
  perform e2e.note('owner edits bio', (select bio from public.profiles where id = e2e.uid(1)) = 'نبذة اختبار', r);
  r := e2e.req('PATCH', '/rest/v1/profiles?id=eq.' || e2e.uid(1), e2e.tok(2), jsonb_build_object('bio', 'hacked'));
  perform e2e.note('other user cannot edit profile', (select bio from public.profiles where id = e2e.uid(1)) = 'نبذة اختبار', r);
  r := e2e.req('PATCH', '/rest/v1/profiles?id=eq.' || e2e.uid(1), e2e.tok(1), jsonb_build_object('rating', 3000));
  perform e2e.note('player cannot edit own rating', (select rating from public.profiles where id = e2e.uid(1)) = 1000, r);
  r := e2e.get(2, 'account_private?select=*');
  perform e2e.note('private account data of others not readable', not coalesce(r->'body' @> jsonb_build_array(jsonb_build_object('user_id', e2e.uid(1))), false), r);
  r := e2e.rpc(2, 'admin_overview');                                              perform e2e.note('normal user denied admin', r->>'status' <> '200', r);
  return (select jsonb_agg(jsonb_build_object('step', step, 'ok', ok) order by id) from e2e.log);
end $f$;

-- Step 4: room, joins and a simultaneous race for one seat (three requests fired together through pg_net).
create or replace function e2e.room1() returns jsonb language plpgsql as $f$
declare r jsonb; rid uuid; code text; i int;
begin
  perform e2e.beat();
  r := e2e.api(1, 'room_create', jsonb_build_object('kind', 'private', 'chat_mode', 'open')); perform e2e.note('room_create', r->>'status' = '200', r);
  rid := (r->'body'->>'id')::uuid; code := r->'body'->>'code';
  insert into e2e.kv values ('room', jsonb_build_object('id', rid, 'code', code)) on conflict (k) do update set v = excluded.v;
  insert into e2e.kv values ('stats', '{}') on conflict (k) do update set v = '{}';
  for i in 2..4 loop r := e2e.api(i, 'room_join', jsonb_build_object('code', code)); perform e2e.note('join by code ' || i, r->>'status' = '200', r); end loop;
  r := e2e.api(1, 'room_sit', jsonb_build_object('id', rid, 'seat', 3));
  perform e2e.note('moving seat frees the old seat', (select (seats->0) = 'null'::jsonb and (seats->3->>'uid')::uuid = e2e.uid(1) from public.rooms where id = rid), r);
  perform e2e.api(1, 'room_sit', jsonb_build_object('id', rid, 'seat', 0));
  insert into e2e.kv values ('race', (select jsonb_agg(net.http_post('PROJECT_URL/functions/v1/api',
      jsonb_build_object('action', 'room_sit', 'id', rid, 'seat', 2),
      headers := jsonb_build_object('Content-Type', 'application/json', 'apikey', 'PUBLISHABLE_KEY', 'Authorization', 'Bearer ' || e2e.tok(u.n)),
      timeout_milliseconds := 20000)) from e2e.users u where n in (2, 3, 4))) on conflict (k) do update set v = excluded.v;
  return (select jsonb_agg(jsonb_build_object('step', step, 'ok', ok) order by id) from e2e.log where at > now() - interval '1 minute');
end $f$;

-- Step 5: seating, readiness, owner-only start.
create or replace function e2e.room2() returns jsonb language plpgsql as $f$
declare r jsonb; rid uuid := (select (v->>'id')::uuid from e2e.kv where k='room'); i int; others int[];
begin
  perform e2e.beat();
  perform e2e.note('simultaneous seat race: exactly one winner',
    (select count(*) filter (where status_code = 200) = 1 and count(*) = 3 from net._http_response where id in (select (jsonb_array_elements_text(v))::bigint from e2e.kv where k='race')), null);
  others := array(select n from e2e.users u where n > 1 and not exists (select 1 from public.rooms where id = rid and seats->2->>'uid' = u.id::text) order by n);
  r := e2e.api(others[1], 'room_sit', jsonb_build_object('id', rid, 'seat', 1)); perform e2e.note('sit seat 1', r->>'status'='200', r);
  r := e2e.api(others[2], 'room_sit', jsonb_build_object('id', rid, 'seat', 3)); perform e2e.note('sit seat 3', r->>'status'='200', r);
  r := e2e.api(others[2], 'room_sit', jsonb_build_object('id', rid, 'seat', 1)); perform e2e.note('taken seat rejected', r->'body'->>'error'='seat_taken', r);
  r := e2e.api(1, 'room_start', jsonb_build_object('id', rid)); perform e2e.note('start refused before all ready', r->'body'->>'error'='not_all_ready', r);
  for i in 1..4 loop r := e2e.api(i, 'room_ready', jsonb_build_object('id', rid, 'ready', true)); perform e2e.note('ready ' || i, r->>'status'='200', r); end loop;
  r := e2e.api(2, 'room_start', jsonb_build_object('id', rid)); perform e2e.note('non-owner cannot start', r->'body'->>'error'='owner_only', r);
  r := e2e.api(1, 'room_start', jsonb_build_object('id', rid)); perform e2e.note('owner starts match', r->>'status'='200', r);
  return (select jsonb_agg(jsonb_build_object('step', step, 'ok', ok) order by id) from e2e.log where at > now() - interval '1 minute');
end $f$;

-- Step 6: play for p_secs seconds. Each player reads only their own hand, tries cards until the server accepts one
-- (counting illegal_move rejections), sometimes plays out of turn (must fail) and resends a request id (must be ignored).
create or replace function e2e.play_loop(p_secs int default 40) returns jsonb language plpgsql as $f$
declare rid uuid := (select (kv.v->>'id')::uuid from e2e.kv kv where kv.k='room'); st jsonb; q jsonb; rstatus text; who int; other int;
  r jsonb; hand jsonb; c text; bv jsonb; t0 timestamptz := clock_timestamp(); rq text; opts jsonb; played boolean;
begin
  while clock_timestamp() < t0 + make_interval(secs => p_secs) loop
    perform e2e.beat();
    select rm.state, rm.status into st, rstatus from public.rooms rm where rm.id = rid;
    if rstatus <> 'playing' then return jsonb_build_object('done', true, 'status', rstatus, 'scores', st->'scores', 'winner', st->'winner', 'stats', (select kv.v from e2e.kv kv where kv.k='stats')); end if;
    q := st->'req';
    if q is null then perform pg_sleep(0.5); continue; end if;
    if q->>'k' = 'next' then
      r := e2e.api(1, 'play', jsonb_build_object('id', rid, 'kind', 'next', 'reqId', (q->>'id')::int, 'rid', gen_random_uuid()));
      perform e2e.bump(case when r->>'status' = '200' then 'next_ok' else 'next_err' end);
      continue;
    end if;
    who := e2e.nseat((q->>'p')::int); other := e2e.nseat(((q->>'p')::int + 1) % 4);
    if q->>'k' = 'bid' then
      opts := q->'d'->'opts';
      bv := jsonb_build_object('t', case when opts ? 'sun' then 'sun' when opts ? 'hokm' then 'hokm' else 'pass' end);
    elsif q->>'k' = 'double' then bv := 'false'::jsonb;
    else
      r := e2e.get(who, 'room_hands?select=seat,cards&room_id=eq.' || rid);
      if jsonb_array_length(r->'body') <> 1 or (r->'body'->0->>'seat')::int <> (q->>'p')::int then perform e2e.bump('secrecy_fail'); perform e2e.note('secrecy', false, r); else perform e2e.bump('secrecy_ok'); end if;
      hand := r->'body'->0->'cards';
      if random() < 0.15 then
        r := e2e.api(other, 'play', jsonb_build_object('id', rid, 'kind', 'card', 'v', hand->>0, 'rid', gen_random_uuid()));
        perform e2e.bump(case when r->>'status' = '200' then 'out_of_turn_accepted' else 'out_of_turn_rejected' end);
      end if;
      played := false;
      for c in select jsonb_array_elements_text(hand) loop
        rq := gen_random_uuid()::text;
        r := e2e.api(who, 'play', jsonb_build_object('id', rid, 'kind', 'card', 'v', c, 'reqId', (q->>'id')::int, 'rid', rq));
        if r->>'status' = '200' and coalesce((r->'body'->>'stale')::boolean, false) = false then
          played := true; perform e2e.bump('cards');
          if random() < 0.1 then
            r := e2e.api(who, 'play', jsonb_build_object('id', rid, 'kind', 'card', 'v', c, 'rid', rq));
            perform e2e.bump(case when (r->'body'->>'duplicate')::boolean then 'dup_ignored' else 'dup_not_flagged' end);
          end if;
          exit;
        elsif r->'body'->>'error' = 'illegal_move' then perform e2e.bump('illegal_rejected');
        else perform e2e.bump('card_other'); exit; end if;
      end loop;
      if not played then perform e2e.bump('no_card_played'); end if;
      continue;
    end if;
    r := e2e.api(who, 'play', jsonb_build_object('id', rid, 'kind', q->>'k', 'v', bv, 'reqId', (q->>'id')::int, 'rid', gen_random_uuid()));
    perform e2e.bump(case when r->>'status' = '200' then (q->>'k') || '_ok' else (q->>'k') || '_err' end);
  end loop;
  select rm.state into st from public.rooms rm where rm.id = rid;
  return jsonb_build_object('done', false, 'scores', st->'scores', 'round', st->'round', 'stats', (select kv.v from e2e.kv kv where kv.k='stats'));
end $f$;

-- Run, one statement at a time:
-- 1) select e2e.make_users();
-- 2) select n, e2e.rpc(n, 'complete_onboarding', jsonb_build_object('p_username', 'e2e_' || n || to_char(now(),'MIss'), 'p_display', 'اختبار ' || n))->'status' from generate_series(1,4) n;
-- 3) select e2e.social();
-- 4) select e2e.room1();
-- 5) select e2e.room2();
-- 6) select e2e.play_loop(45);   -- repeat until "done": true
-- 7) verify the result was stored once:
--    select m.status, m.score0, m.score1, (select json_agg(json_build_object('n',u.n,'res',mp.result,'xp',mp.xp_gained,'games',p.games,'wins',p.wins))
--      from public.match_players mp join e2e.users u on u.id=mp.user_id join public.profiles p on p.id=mp.user_id where mp.match_id=m.id)
--    from public.matches m where m.id = (select match_id from public.rooms where id = (select (v->>'id')::uuid from e2e.kv where k='room'));
