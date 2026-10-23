// Diwaniya game server (Supabase Edge Function "api").
// It is the only writer of rooms, hidden hands, matches and results. Every request is authenticated and checked here.
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import * as E from './engine.js';

const URL_ = Deno.env.get('SUPABASE_URL')!;
const db = createClient(URL_, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
// Owner email lives in public.app_settings (no client access); the sweep secret lives in Supabase Vault.
async function ownerEmail() {
  const { data } = await db.from('app_settings').select('value').eq('key', 'owner_email').maybeSingle();
  return (data?.value || '').trim().toLowerCase();
}
async function cronOk(req: Request) {
  const h = req.headers.get('x-cron-secret') || '';
  if (!h) return false;
  const { data } = await db.rpc('cron_secret_ok', { p: h });
  return data === true;
}
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-cron-secret',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });
class Fail extends Error { constructor(public code: string, public status = 400) { super(code); } }
class Conflict extends Error {}

/* ---------------- policy constants (documented in docs/POLICIES.md) ---------------- */
const EVENT_MS = 750;            // replay allowance per event before a human's clock starts
const OFFLINE_MS = 60_000;       // no heartbeat for this long = disconnected
const RECONNECT_MS = 180_000;    // disconnected longer than this = seat abandoned (bot plays, result counts as a loss)
const MAX_MISSES = 3;            // consecutive timeouts that also abandon the seat
const NEXT_MS = 20_000;          // round summary pause
const rnd = () => crypto.getRandomValues(new Uint32Array(1))[0] / 2 ** 32;

type Seat = { uid: string; name: string; ready?: boolean; abandoned?: boolean } | null;
type Room = { id: string; code: string; kind: string; owner: string | null; status: string; rules: any; chat_mode: string; seats: Seat[]; members: string[]; match_id: string | null; state: any; version: number };
type Me = { id: string; username: string; display: string; email: string };

/* ---------------- auth ---------------- */
async function userFrom(req: Request): Promise<Me> {
  const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  if (!token) throw new Fail('not_signed_in', 401);
  const { data, error } = await db.auth.getUser(token);
  if (error || !data.user) throw new Fail('not_signed_in', 401);
  const { data: p } = await db.from('profiles').select('id, username, display_name').eq('id', data.user.id).maybeSingle();
  if (!p) throw new Fail('no_profile', 403);
  return { id: p.id, username: p.username, display: p.display_name || p.username, email: (data.user.email || '').toLowerCase() };
}
async function isBanned(uid: string) {
  const { data } = await db.from('account_private').select('ban_until, ban_permanent').eq('user_id', uid).maybeSingle();
  return !!data && (data.ban_permanent || (data.ban_until && new Date(data.ban_until) > new Date()));
}
async function staffRole(uid: string) {
  const { data } = await db.from('admin_roles').select('role').eq('user_id', uid).maybeSingle();
  return data ? data.role as string : null;
}
const rank = (r: string | null) => (r === 'owner' ? 3 : r === 'admin' ? 2 : r === 'moderator' ? 1 : 0);
async function logError(source: string, e: unknown, context: Record<string, unknown> = {}) {
  try { await db.from('server_errors').insert({ source, message: String((e as Error)?.message || e).slice(0, 500), context }); } catch { /* ignore */ }
}

/* ---------------- room persistence ---------------- */
async function loadRoom(id: string) {
  const { data: r } = await db.from('rooms').select('*').eq('id', id).maybeSingle();
  if (!r) throw new Fail('room_not_found', 404);
  const { data: s } = await db.from('room_secrets').select('g, meta').eq('room_id', id).maybeSingle();
  return { r: r as Room, G: s ? s.g : null, meta: (s && s.meta) || {} };
}
const isBot = (r: Room) => (p: number) => !r.seats[p] || !!r.seats[p]!.abandoned;
const seatOf = (r: Room, uid: string) => r.seats.findIndex((s) => s && s.uid === uid);

function stampDeadline(r: Room, G: any) {
  const q = G.req;
  if (!q || r.status !== 'playing') { G.deadline = null; return; }
  if (G.deadlineFor === q.id) return;
  const fresh = G.evSeq - (G.lastDeadlineEv || 0);
  const base = q.k === 'next' ? NEXT_MS : (G.rules.turnSeconds || 30) * 1000;
  G.deadline = Date.now() + base + Math.min(fresh, 24) * EVENT_MS;
  G.deadlineFor = q.id; G.lastDeadlineEv = G.evSeq;
}
async function save(r: Room, G: any, meta: any, oldHands: string[][] | null, opts: { forceHands?: boolean; fields?: Record<string, unknown> } = {}) {
  const fields: Record<string, unknown> = { seats: r.seats, members: r.members, status: r.status, owner: r.owner ?? '', rules: r.rules, chat_mode: r.chat_mode, match_id: r.match_id ?? '', ...(opts.fields || {}) };
  let hands: unknown[] | null = null, events: unknown[] | null = null;
  if (G) {
    stampDeadline(r, G);
    const pub: any = E.publicView(G);
    pub.deadline = G.deadline; pub.serverNow = Date.now();
    fields.state = pub;
    hands = [0, 1, 2, 3].filter((s) => opts.forceHands || !oldHands || oldHands[s].join() !== G.hands[s].join())
      .map((s) => ({ seat: s, user_id: r.seats[s] && !r.seats[s]!.abandoned ? r.seats[s]!.uid : '', cards: G.hands[s] }));
    const from = meta.evSaved || 0;
    events = G.ev.filter((e: any[]) => e[0] > from).map((e: any[]) => ({ seq: e[0], kind: e[1], data: e.slice(2) }));
    if (G.dealtLog && G.dealtLog.length > (meta.dealsSaved || 0)) {
      for (let i = meta.dealsSaved || 0; i < G.dealtLog.length; i++) events.push({ seq: 1_000_000 + i + 1, kind: 'hands', data: G.dealtLog[i] });
      meta.dealsSaved = G.dealtLog.length;
    }
    meta.evSaved = G.evSeq;
  } else if (opts.fields && 'state' in opts.fields) fields.state = opts.fields.state;
  const { data, error } = await db.rpc('save_room', { p_id: r.id, p_version: r.version, p_fields: fields, p_g: G, p_meta: meta, p_hands: hands, p_match: r.match_id, p_events: events });
  if (error) throw error;
  if (!data) throw new Conflict();
  r.version++;
}
/** Load → change → save with optimistic locking. The callback may return {skip, out, forceHands}. */
async function mutate(id: string, fn: (r: Room, G: any, meta: any) => any) {
  for (let attempt = 0; attempt < 6; attempt++) {
    const { r, G, meta } = await loadRoom(id);
    const old = G ? G.hands.map((h: string[]) => h.slice()) : null;
    const res = (await fn(r, G, meta)) || {};
    if (res.skip) return res.out || { ok: true };
    const g2 = res.G !== undefined ? res.G : G;
    let finalize: any = null;
    if (g2 && r.status === 'playing') {
      E.runBots(g2, isBot(r), 'mid', rnd);
      finalize = maybeFinish(r, g2);
    }
    try {
      await save(r, g2, meta, res.G !== undefined ? null : old, { forceHands: res.forceHands });
      if (finalize) {
        const { error } = await db.rpc('finalize_match', { p_match: r.match_id, p_result: finalize });
        if (error) await logError('finalize_match', error, { room: r.id });
      }
      return { ok: true, ...(res.out || {}) };
    } catch (e) {
      if (!(e instanceof Conflict)) throw e;
      await new Promise((ok) => setTimeout(ok, 40 + Math.random() * 160));
    }
  }
  throw new Fail('busy', 409);
}
/** When the match is over (or every human is gone) build the verified result exactly once. */
function maybeFinish(r: Room, G: any) {
  const allGone = r.seats.every((s) => !s || s.abandoned);
  if (G.recorded || !(G.over || allGone)) return null;
  G.recorded = true;
  r.status = 'finished';
  const players = r.seats.map((s, p) => {
    const mine = (G.stats?.rounds || []).filter((x: any) => x.buyer === p);
    const won = (x: any) => x.outcome === 'made' || x.outcome === 'kaboot';
    return { uid: s!.uid, seat: p, team: p % 2, abandoned: !!s!.abandoned,
      sun_rounds: mine.filter((x: any) => x.type === 'sun').length, sun_won: mine.filter((x: any) => x.type === 'sun' && won(x)).length,
      hokm_rounds: mine.filter((x: any) => x.type === 'hokm').length, hokm_won: mine.filter((x: any) => x.type === 'hokm' && won(x)).length };
  });
  return {
    status: G.over ? 'finished' : 'abandoned', score0: G.scores[0], score1: G.scores[1], winner_team: G.over ? G.winner : null,
    gahwa: !!G.gahwa && G.over, kab: G.stats?.kab || [0, 0], rounds: G.log, players,
  };
}

/* ---------------- room actions ---------------- */
function makeCode() { const a = 'abcdefghjkmnpqrstuvwxyz23456789'; let s = ''; for (let i = 0; i < 6; i++) s += a[Math.floor(rnd() * a.length)]; return s; }
const cleanRules = (x: any) => E.makeRules(x && typeof x === 'object' ? x : {});

async function roomCreate(me: Me, b: any) {
  if (await isBanned(me.id)) throw new Fail('banned', 403);
  const kind = b.kind === 'public' ? 'public' : 'private';
  const chat = ['open', 'quick', 'off'].includes(b.chat_mode) ? b.chat_mode : 'open';
  for (let i = 0; i < 6; i++) {
    const { data, error } = await db.from('rooms').insert({
      code: makeCode(), kind, owner: me.id, rules: cleanRules(b.rules), chat_mode: chat,
      seats: [{ uid: me.id, name: me.display, ready: false }, null, null, null], members: [me.id],
    }).select('id, code').single();
    if (!error && data) return { ok: true, id: data.id, code: data.code };
  }
  throw new Fail('create_failed', 500);
}
async function resolveRoomId(b: any) {
  if (b.id) return b.id;
  const code = String(b.code || '').trim().toLowerCase();
  const { data } = await db.from('rooms').select('id').eq('code', code).maybeSingle();
  if (!data) throw new Fail('room_not_found', 404);
  return data.id;
}
async function roomJoin(me: Me, b: any) {
  if (await isBanned(me.id)) throw new Fail('banned', 403);
  const id = await resolveRoomId(b);
  return mutate(id, (r) => {
    if (r.status === 'closed') throw new Fail('room_closed');
    if (r.kind === 'ranked' || r.kind === 'friendly') { if (seatOf(r, me.id) < 0 && !r.members.includes(me.id)) throw new Fail('room_private'); }
    if (!r.members.includes(me.id)) r.members.push(me.id);
    return { out: { id: r.id, code: r.code } };
  });
}
async function roomSit(me: Me, b: any) {
  const seat = Number(b.seat);
  if (!(seat >= 0 && seat < 4)) throw new Fail('bad_seat');
  return mutate(b.id, (r) => {
    if (r.status !== 'waiting') throw new Fail('not_waiting');
    if (!r.members.includes(me.id)) throw new Fail('not_member');
    if (r.seats[seat]) throw new Fail('seat_taken');
    const cur = seatOf(r, me.id);
    if (cur >= 0) r.seats[cur] = null;                    // one account can never hold two seats
    r.seats[seat] = { uid: me.id, name: me.display, ready: false };
    for (const s of r.seats) if (s) s.ready = false;      // seating changes reset readiness
  });
}
async function roomStand(me: Me, b: any) {
  return mutate(b.id, (r) => {
    if (r.status !== 'waiting') throw new Fail('not_waiting');
    const cur = seatOf(r, me.id); if (cur < 0) return { skip: true };
    r.seats[cur] = null;
  });
}
async function roomReady(me: Me, b: any) {
  return mutate(b.id, (r) => {
    if (r.status !== 'waiting') throw new Fail('not_waiting');
    const cur = seatOf(r, me.id); if (cur < 0) throw new Fail('not_seated');
    r.seats[cur]!.ready = !!b.ready;
  });
}
async function roomSettings(me: Me, b: any) {
  return mutate(b.id, (r) => {
    if (r.owner !== me.id) throw new Fail('owner_only', 403);
    if (r.status !== 'waiting') throw new Fail('not_waiting');
    if (b.rules) r.rules = cleanRules(b.rules);
    if (['open', 'quick', 'off'].includes(b.chat_mode)) r.chat_mode = b.chat_mode;
    if (b.kind === 'public' || b.kind === 'private') r.kind = b.kind;
    for (const s of r.seats) if (s) s.ready = false;      // everyone re-confirms after a rule change
  });
}
async function roomKick(me: Me, b: any) {
  return mutate(b.id, (r) => {
    if (r.owner !== me.id) throw new Fail('owner_only', 403);
    if (r.status !== 'waiting') throw new Fail('not_waiting');
    const s = Number(b.seat); if (!(s >= 0 && s < 4) || !r.seats[s] || r.seats[s]!.uid === me.id) throw new Fail('bad_seat');
    r.seats[s] = null;
  });
}
async function roomTransfer(me: Me, b: any) {
  return mutate(b.id, (r) => {
    if (r.owner !== me.id) throw new Fail('owner_only', 403);
    if (!r.seats.some((s) => s && s.uid === b.to)) throw new Fail('bad_target');
    r.owner = b.to;
  });
}
async function startMatchIn(r: Room) {
  const G = E.newGame({ rules: r.rules, rnd });
  E.startRound(G, rnd);
  const players = r.seats.map((s, p) => ({ seat: p, uid: s!.uid, name: s!.name }));
  const { data: season } = await db.from('seasons').select('id').eq('active', true).maybeSingle();
  const { data: m, error } = await db.from('matches').insert({
    room_id: r.id, ranked: r.kind === 'ranked', season_id: season ? season.id : null, rules: G.rules, players, player_ids: players.map((x) => x.uid),
  }).select('id').single();
  if (error) throw error;
  r.match_id = m.id; r.status = 'playing';
  for (const s of r.seats) { s!.ready = true; s!.abandoned = false; }
  return G;
}
async function roomStart(me: Me, b: any) {
  return mutate(b.id, async (r, _G, meta) => {
    if (r.owner !== me.id) throw new Fail('owner_only', 403);
    if (r.status !== 'waiting') throw new Fail('not_waiting');
    if (r.seats.some((s) => !s)) throw new Fail('need_four');
    if (r.seats.some((s) => !s!.ready)) throw new Fail('not_all_ready');
    const uids = r.seats.map((s) => s!.uid);
    if (new Set(uids).size !== 4) throw new Fail('duplicate_player');
    for (const u of uids) if (await isBanned(u)) throw new Fail('player_banned');
    Object.assign(meta, { evSaved: 0, dealsSaved: 0, rids: [], misses: {}, offlineSince: {} });
    return { G: await startMatchIn(r), forceHands: true };
  });
}
async function roomLeave(me: Me, b: any) {
  return mutate(b.id, (r, G) => {
    const cur = seatOf(r, me.id);
    if (r.status === 'waiting') {
      if (cur >= 0) r.seats[cur] = null;
      r.members = r.members.filter((u) => u !== me.id);
      if (r.owner === me.id) {
        const next = r.seats.find((s) => s);
        if (next) r.owner = next.uid; else r.status = 'closed';
      }
      return;
    }
    if (r.status === 'playing' && cur >= 0 && G) {
      if (!r.seats[cur]!.abandoned) { r.seats[cur]!.abandoned = true; E.addEvent(G, 'left', cur); }
      return { forceHands: true };
    }
    r.members = r.members.filter((u) => u !== me.id);
  });
}
async function roomClose(me: Me, b: any) {
  return mutate(b.id, (r) => {
    if (r.owner !== me.id) throw new Fail('owner_only', 403);
    if (r.status === 'playing') throw new Fail('match_running');
    r.status = 'closed';
  });
}
async function roomRematch(me: Me, b: any) {
  return mutate(b.id, (r) => {
    if (r.owner !== me.id) throw new Fail('owner_only', 403);
    if (r.status !== 'finished') throw new Fail('not_finished');
    if (r.kind === 'ranked' || r.kind === 'friendly') throw new Fail('use_matchmaking');
    r.status = 'waiting'; r.match_id = null;
    r.seats = r.seats.map((s) => (s && !s.abandoned ? { uid: s.uid, name: s.name, ready: false } : null));
    return { G: null, forceHands: true };
  });
}

/* ---------------- playing ---------------- */
async function play(me: Me, b: any) {
  const rid = typeof b.rid === 'string' ? b.rid.slice(0, 40) : '';
  return mutate(b.id, (r, G, meta) => {
    if (!G || r.status !== 'playing') throw new Fail('not_playing');
    const p = seatOf(r, me.id);
    if (p < 0) throw new Fail('not_seated', 403);
    if (r.seats[p]!.abandoned) throw new Fail('seat_abandoned', 403);
    meta.rids = meta.rids || [];
    if (rid && meta.rids.includes(rid)) return { skip: true, out: { ok: true, duplicate: true } };
    if (b.reqId && G.req && G.req.id !== b.reqId) return { skip: true, out: { ok: true, stale: true } };
    try { E.act(G, b.kind === 'next' ? -1 : p, b.kind, b.v, rnd); }
    catch { throw new Fail('illegal_move'); }
    if (rid) { meta.rids.push(rid); if (meta.rids.length > 300) meta.rids.splice(0, meta.rids.length - 300); }
    meta.misses = meta.misses || {}; meta.misses[p] = 0;
  });
}
/** Applies the timeout / disconnect policy. Called by players' clients and by the scheduled sweep. */
async function enforce(id: string) {
  return mutate(id, async (r, G, meta) => {
    if (!G || r.status !== 'playing') return { skip: true };
    let changed = false, forceHands = false;
    // disconnects: no heartbeat for OFFLINE_MS starts the reconnect window
    const uids = r.seats.filter((s) => s && !s.abandoned).map((s) => s!.uid);
    const { data: seen } = await db.from('account_private').select('user_id, last_seen').in('user_id', uids);
    const last = new Map((seen || []).map((x: any) => [x.user_id, x.last_seen ? Date.parse(x.last_seen) : 0]));
    meta.offlineSince = meta.offlineSince || {};
    const now = Date.now();
    r.seats.forEach((s, p) => {
      if (!s || s.abandoned) return;
      const ls = last.get(s.uid) || 0;
      if (now - ls > OFFLINE_MS) {
        if (!meta.offlineSince[p]) { meta.offlineSince[p] = now - OFFLINE_MS; changed = true; }
        if (now - meta.offlineSince[p] > RECONNECT_MS) { s.abandoned = true; E.addEvent(G, 'left', p); changed = true; forceHands = true; }
      } else if (meta.offlineSince[p]) { delete meta.offlineSince[p]; changed = true; }
    });
    // timer
    const q = G.req;
    if (q && G.deadline && now >= G.deadline) {
      if (q.k === 'next') { E.act(G, -1, 'next', true, rnd); changed = true; }
      else if (r.seats[q.p] && !r.seats[q.p]!.abandoned) {
        E.act(G, q.p, q.k, E.botDecision(G, 'mid', rnd), rnd);
        meta.misses = meta.misses || {}; meta.misses[q.p] = (meta.misses[q.p] || 0) + 1;
        if (meta.misses[q.p] >= MAX_MISSES) { r.seats[q.p]!.abandoned = true; E.addEvent(G, 'left', q.p); forceHands = true; }
        else E.addEvent(G, 'afk', q.p);
        changed = true;
      }
    }
    if (!changed) return { skip: true };
    return { forceHands };
  });
}

/* ---------------- matchmaking ---------------- */
async function queueJoin(me: Me, b: any) {
  if (await isBanned(me.id)) throw new Fail('banned', 403);
  const mode = b.mode === 'ranked' ? 'ranked' : 'friendly';
  const { data: busy } = await db.from('rooms').select('id').eq('status', 'playing').contains('members', [me.id]).limit(5);
  for (const x of busy || []) {
    const { data: rr } = await db.from('rooms').select('seats').eq('id', x.id).single();
    if (rr && (rr.seats as Seat[]).some((s) => s && s.uid === me.id && !s.abandoned)) throw new Fail('already_playing');
  }
  const { data: p } = await db.from('profiles').select('rating').eq('id', me.id).single();
  await db.from('queue').upsert({ user_id: me.id, mode, rating: p!.rating, created_at: new Date().toISOString(), matched_room: null });
  return queuePoll(me);
}
async function queueLeave(me: Me) {
  await db.from('queue').delete().eq('user_id', me.id).is('matched_room', null);
  return { ok: true };
}
async function queuePoll(me: Me) {
  const { data: q } = await db.from('queue').select('*').eq('user_id', me.id).maybeSingle();
  if (!q) return { ok: true, queued: false };
  if (q.matched_room && q.matched_room !== '00000000-0000-0000-0000-000000000000') return { ok: true, queued: false, room: q.matched_room };
  await tryMatch(q.mode);
  const { data: q2 } = await db.from('queue').select('*').eq('user_id', me.id).maybeSingle();
  const { count } = await db.from('queue').select('*', { count: 'exact', head: true }).eq('mode', q.mode).is('matched_room', null);
  if (q2 && q2.matched_room && q2.matched_room !== '00000000-0000-0000-0000-000000000000') return { ok: true, queued: false, room: q2.matched_room };
  return { ok: true, queued: true, mode: q.mode, waiting: count || 0, since: q.created_at };
}
async function tryMatch(mode: string) {
  const { data: picked } = await db.rpc('queue_pick', { p_mode: mode });
  if (!picked || picked.length !== 4) return;
  const { data: profs } = await db.from('profiles').select('id, username, display_name, rating').in('id', picked);
  const ps = (profs || []).sort((a: any, b: any) => b.rating - a.rating);
  const order = [ps[0], ps[1], ps[3], ps[2]];               // seats 0/2 = strongest+weakest, 1/3 = the middle two
  const seats: Seat[] = order.map((p: any) => ({ uid: p.id, name: p.display_name || p.username, ready: true }));
  const rules = E.makeRules({});
  const { data: room, error } = await db.from('rooms').insert({
    code: makeCode(), kind: mode, owner: null, rules, chat_mode: mode === 'ranked' ? 'quick' : 'open', seats, members: picked, status: 'waiting',
  }).select('*').single();
  if (error) { await logError('matchmaking', error); return; }
  const r = room as Room;
  const G = await startMatchIn(r);
  E.runBots(G, isBot(r), 'mid', rnd);
  await save(r, G, { evSaved: 0, dealsSaved: 0, rids: [], misses: {}, offlineSince: {} }, null, { forceHands: true });
  await db.from('queue').update({ matched_room: r.id }).in('user_id', picked);
  for (const u of picked) await db.rpc('notify_user', { p_user: u, p_kind: 'match_found', p_data: { room_id: r.id, code: r.code, mode } });
}

/* ---------------- social and admin actions that remove rows ---------------- */
async function friendRemove(me: Me, b: any) {
  const [a, c] = [me.id, String(b.target)].sort();
  await db.from('friendships').delete().eq('a', a).eq('b', c);
  return { ok: true };
}
async function block(me: Me, b: any) {
  const t = String(b.target); if (t === me.id) throw new Fail('self');
  const [a, c] = [me.id, t].sort();
  await db.from('blocks').upsert({ blocker: me.id, blocked: t });
  await db.from('friendships').delete().eq('a', a).eq('b', c);
  await db.from('friend_requests').update({ status: 'cancelled', responded_at: new Date().toISOString() })
    .eq('status', 'pending').or(`and(from_id.eq.${me.id},to_id.eq.${t}),and(from_id.eq.${t},to_id.eq.${me.id})`);
  return { ok: true };
}
async function unblock(me: Me, b: any) {
  await db.from('blocks').delete().eq('blocker', me.id).eq('blocked', String(b.target));
  return { ok: true };
}
async function audit(actor: string, action: string, target: string, details: Record<string, unknown>) {
  await db.from('audit_log').insert({ actor, action, target, details });
}
async function adminBan(me: Me, b: any) {
  const role = await staffRole(me.id); if (!rank(role)) throw new Fail('forbidden', 403);
  const reason = String(b.reason || '').trim(); if (reason.length < 3) throw new Fail('reason_required');
  const hours = b.hours === null || b.hours === undefined ? null : Math.max(1, Math.min(24 * 365, Number(b.hours) | 0));
  if (rank(await staffRole(b.user)) && rank(role) < 3) throw new Fail('forbidden', 403);
  if ((hours === null || hours > 72) && rank(role) < 2) throw new Fail('forbidden', 403);
  await db.from('account_private').upsert({ user_id: b.user }, { onConflict: 'user_id', ignoreDuplicates: true });
  await db.from('account_private').update({ ban_permanent: hours === null, ban_until: hours === null ? null : new Date(Date.now() + hours * 3600e3).toISOString(), ban_reason: reason }).eq('user_id', b.user);
  await db.from('queue').delete().eq('user_id', b.user);
  await audit(me.id, 'ban', b.user, { hours, reason });
  return { ok: true };
}
async function adminSetRole(me: Me, b: any) {
  if (rank(await staffRole(me.id)) < 3) throw new Fail('forbidden', 403);
  if (rank(await staffRole(b.user)) === 3) throw new Fail('forbidden', 403);
  if (b.role === null) await db.from('admin_roles').delete().eq('user_id', b.user);
  else if (['admin', 'moderator'].includes(b.role)) await db.from('admin_roles').upsert({ user_id: b.user, role: b.role, granted_by: me.id });
  else throw new Fail('bad_role');
  await audit(me.id, 'set_role', b.user, { role: b.role });
  return { ok: true };
}
async function bootstrap(me: Me) {
  const owner = await ownerEmail();
  if (owner && me.email === owner) {
    const role = await staffRole(me.id);
    if (role !== 'owner') { await db.from('admin_roles').upsert({ user_id: me.id, role: 'owner' }); await audit(me.id, 'owner_bootstrap', me.id, {}); }
  }
  return { ok: true, role: await staffRole(me.id) };
}
async function deleteAccount(me: Me, b: any) {
  if (String(b.confirm || '') !== me.username) throw new Fail('confirm_mismatch');
  const { data: rooms } = await db.from('rooms').select('id').eq('status', 'playing').contains('members', [me.id]);
  for (const x of rooms || []) await roomLeave(me, { id: x.id }).catch(() => {});
  const { data: files } = await db.storage.from('avatars').list(me.id);
  if (files && files.length) await db.storage.from('avatars').remove(files.map((f: any) => `${me.id}/${f.name}`));
  await audit(me.id, 'delete_account', me.id, { username: me.username });
  const { error } = await db.auth.admin.deleteUser(me.id);
  if (error) throw new Fail('delete_failed', 500);
  return { ok: true };
}

/* ---------------- scheduled sweep ---------------- */
async function sweep() {
  const { data: playing } = await db.from('rooms').select('id').eq('status', 'playing').limit(200);
  for (const x of playing || []) await enforce(x.id).catch((e) => logError('sweep_enforce', e, { room: x.id }));
  const stale = new Date(Date.now() - 2 * 3600e3).toISOString();
  await db.from('rooms').update({ status: 'closed' }).eq('status', 'waiting').lt('updated_at', stale);
  await db.from('queue').delete().lt('created_at', new Date(Date.now() - 15 * 60e3).toISOString());
  for (const mode of ['ranked', 'friendly']) await tryMatch(mode).catch((e) => logError('sweep_match', e));
  return { ok: true, rooms: (playing || []).length };
}

/* ---------------- router ---------------- */
const ACTIONS: Record<string, (me: Me, b: any) => Promise<unknown>> = {
  bootstrap, room_create: roomCreate, room_join: roomJoin, room_sit: roomSit, room_stand: roomStand, room_ready: roomReady,
  room_settings: roomSettings, room_kick: roomKick, room_transfer: roomTransfer, room_start: roomStart, room_leave: roomLeave,
  room_close: roomClose, room_rematch: roomRematch, play, tick: (_me, b) => enforce(b.id),
  queue_join: queueJoin, queue_leave: queueLeave, queue_poll: queuePoll,
  friend_remove: friendRemove, block, unblock, admin_ban: adminBan, admin_set_role: adminSetRole, delete_account: deleteAccount,
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  let action = '';
  try {
    const body = await req.json().catch(() => ({}));
    action = String(body.action || '');
    if (action === 'sweep') {
      if (!(await cronOk(req))) throw new Fail('forbidden', 403);
      return json(await sweep());
    }
    const fn = ACTIONS[action];
    if (!fn) throw new Fail('unknown_action');
    const me = await userFrom(req);
    return json(await fn(me, body));
  } catch (e) {
    if (e instanceof Fail) return json({ error: e.code }, e.status);
    await logError('api:' + action, e);
    return json({ error: 'server_error' }, 500);
  }
});
