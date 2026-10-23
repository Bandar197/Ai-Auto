// Baloot Majlis game server. Every game decision goes through here, so players never see each other's cards.
import { createClient } from 'npm:@supabase/supabase-js@2.45.4';
import * as E from './engine.js';

const db = createClient(Deno.env.get('SUPABASE_URL')!, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!, { auth: { persistSession: false } });
const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (b: unknown, status = 200) => new Response(JSON.stringify(b), { status, headers: { ...CORS, 'Content-Type': 'application/json' } });
class Fail extends Error { constructor(msg: string, public status = 400) { super(msg); } }
class Conflict extends Error {}

const TURN_MS = 35_000, NEXT_MS = 20_000, EVENT_MS = 900, MAX_MISSES = 2;
const USERNAME = /^[A-Za-z0-9_ء-ي٠-٩]{3,14}$/u;
export const emailFor = (u: string) =>
  'p_' + [...new TextEncoder().encode(u.toLowerCase())].map((b) => b.toString(16).padStart(2, '0')).join('') + '@players.baloot-majlis.app';

type Seat = { uid?: string; name?: string; bot?: boolean; was?: string; misses?: number } | null;
type Table = { id: string; code: string; host: string; is_private: boolean; status: string; seats: Seat[]; members: string[]; target: number; level: string; state: any; version: number };

const isBotSeat = (t: Table) => (p: number) => !t.seats[p] || !!t.seats[p]!.bot;
const seatOf = (t: Table, uid: string) => t.seats.findIndex((s) => s && !s.bot && s.uid === uid);
function makeCode() { const a = 'abcdefghjkmnpqrstuvwxyz23456789'; let s = ''; for (let i = 0; i < 6; i++) s += a[Math.floor(Math.random() * a.length)]; return s; }

async function userFrom(req: Request) {
  const token = (req.headers.get('Authorization') || '').replace(/^Bearer\s+/i, '');
  if (!token) throw new Fail('سجّل دخولك أول', 401);
  const { data, error } = await db.auth.getUser(token);
  if (error || !data.user) throw new Fail('سجّل دخولك أول', 401);
  const { data: prof } = await db.from('profiles').select('id, username').eq('id', data.user.id).single();
  if (!prof) throw new Fail('الحساب غير مكتمل', 403);
  return prof as { id: string; username: string };
}
async function load(id: string) {
  const { data: t } = await db.from('game_tables').select('*').eq('id', id).single();
  if (!t) throw new Fail('الطاولة غير موجودة', 404);
  let G = null;
  if (t.status === 'playing' || t.status === 'finished') {
    const { data: s } = await db.from('game_secrets').select('g').eq('table_id', id).single();
    G = s ? s.g : null;
  }
  return { t: t as Table, G };
}
/** Stamp a turn deadline, then save atomically. Returns false on a version conflict. */
async function save(t: Table, G: any, oldHands: string[][] | null, extra: Record<string, unknown> = {}) {
  const fields: Record<string, unknown> = { seats: t.seats, members: t.members, status: t.status, host: t.host, ...extra };
  let hands: unknown[] | null = null;
  if (G) {
    const q = G.req;
    if (q && (q.k === 'next' || !isBotSeat(t)(q.p))) {
      if (G.deadlineFor !== q.id) {
        const newEvents = G.evSeq - (G.lastDeadlineEv || 0);
        G.deadline = Date.now() + (q.k === 'next' ? NEXT_MS : TURN_MS) + Math.min(newEvents, 30) * EVENT_MS;
        G.deadlineFor = q.id; G.lastDeadlineEv = G.evSeq;
      }
    } else { G.deadline = null; G.deadlineFor = null; }
    const pub = E.publicView(G) as any;
    pub.deadline = G.deadline;
    fields.state = pub;
    hands = [0, 1, 2, 3]
      .filter((s) => !oldHands || oldHands[s].join() !== G.hands[s].join() || extra.forceHands)
      .map((s) => ({ seat: s, user_id: t.seats[s] && !t.seats[s]!.bot ? t.seats[s]!.uid : '', cards: G.hands[s] }));
  }
  const { data, error } = await db.rpc('save_game', { p_id: t.id, p_version: t.version, p_fields: fields, p_g: G, p_hands: hands });
  if (error) throw error;
  if (!data) throw new Conflict();
  t.version++;
}
function markOver(t: Table, G: any) {
  if (!G || !G.over || G.recorded) return null;
  G.recorded = true;
  t.status = 'finished';
  const humans = (tm: number) => [0, 1, 2, 3].filter((p) => p % 2 === tm && t.seats[p] && !t.seats[p]!.bot).map((p) => t.seats[p]!.uid);
  return {
    p_table: t.id, p_team0: humans(0), p_team1: humans(1), p_s0: G.scores[0], p_s1: G.scores[1],
    p_kab0: (G.kab || [0, 0])[0], p_kab1: (G.kab || [0, 0])[1],
  };
}
function humanCount(t: Table) { return t.seats.filter((s) => s && !s.bot).length; }

/** Run one mutation with optimistic locking and a few retries. */
async function mutate(id: string, fn: (t: Table, G: any) => Promise<unknown> | unknown) {
  for (let attempt = 0; attempt < 5; attempt++) {
    const { t, G } = await load(id);
    const old = G ? G.hands.map((h: string[]) => h.slice()) : null;
    const res: any = await fn(t, G);
    if (res && res.skip) return res;
    const g2 = res && res.G !== undefined ? res.G : G;
    let result = null;
    if (g2) { E.runBots(g2, isBotSeat(t)); result = markOver(t, g2); }
    try {
      await save(t, g2, res && res.G !== undefined ? null : old, res?.extra || {});
      if (result) await db.rpc('record_match', result);
      return { ok: true, ...(res?.out || {}) };
    }
    catch (e) { if (!(e instanceof Conflict)) throw e; await new Promise((r) => setTimeout(r, 60 + Math.random() * 120)); }
  }
  throw new Fail('ضغط على الطاولة، جرّب مرة ثانية', 409);
}

/* ---------------- actions ---------------- */
async function signup(body: any) {
  const username = String(body.username || '').trim(), password = String(body.password || '');
  if (!USERNAME.test(username)) throw new Fail('اسم المستخدم من ٣ إلى ١٤ حرف أو رقم، بدون مسافات');
  if (password.length < 6) throw new Fail('كلمة المرور لازم ٦ أحرف على الأقل');
  const { data: exists } = await db.from('profiles').select('id').ilike('username', username.replace(/_/g, '\\_')).maybeSingle();
  if (exists) throw new Fail('اسم المستخدم مأخوذ، اختر غيره');
  const { data, error } = await db.auth.admin.createUser({ email: emailFor(username), password, email_confirm: true, user_metadata: { username } });
  if (error || !data.user) throw new Fail(error?.message?.includes('already') ? 'اسم المستخدم مأخوذ، اختر غيره' : 'ما قدرنا ننشئ الحساب');
  const { error: e2 } = await db.from('profiles').insert({ id: data.user.id, username });
  if (e2) { await db.auth.admin.deleteUser(data.user.id); throw new Fail('اسم المستخدم مأخوذ، اختر غيره'); }
  return { ok: true };
}

async function create(me: { id: string; username: string }, body: any) {
  const target = [101, 152, 202].includes(+body.target) ? +body.target : 152;
  const level = ['easy', 'mid', 'hard'].includes(body.level) ? body.level : 'mid';
  for (let i = 0; i < 5; i++) {
    const code = makeCode();
    const { data, error } = await db.from('game_tables').insert({
      code, host: me.id, is_private: !!body.private, target, level,
      seats: [{ uid: me.id, name: me.username }, null, null, null], members: [me.id],
    }).select('id, code').single();
    if (!error && data) return { ok: true, id: data.id, code: data.code };
  }
  throw new Fail('ما قدرنا ننشئ الطاولة');
}

async function join(me: { id: string; username: string }, body: any) {
  let id = body.id;
  if (!id) {
    const code = String(body.code || '').trim().toLowerCase();
    const { data } = await db.from('game_tables').select('id').eq('code', code).maybeSingle();
    if (!data) throw new Fail('ما لقينا طاولة بهذا الكود', 404);
    id = data.id;
  }
  const want = Number.isInteger(body.seat) ? body.seat : null;
  return mutate(id, (t, G) => {
    if (t.status === 'closed') throw new Fail('الطاولة مقفلة');
    if (!t.members.includes(me.id)) t.members.push(me.id);
    let cur = seatOf(t, me.id);
    // back from a disconnect: take your old seat
    if (cur < 0) { const back = t.seats.findIndex((s) => s && s.bot && s.was === me.id); if (back >= 0 && want === null) { t.seats[back] = { uid: me.id, name: me.username }; cur = back; if (G) E.addEvent(G, 'back', back); } }
    if (want !== null && want >= 0 && want < 4 && want !== cur) {
      const s = t.seats[want];
      const free = t.status === 'waiting' ? s === null : !!(s && s.bot);
      if (!free) throw new Fail('الكرسي مو فاضي');
      if (t.status !== 'waiting' && cur >= 0) throw new Fail('أنت جالس على الطاولة');
      if (cur >= 0) t.seats[cur] = null;
      t.seats[want] = { uid: me.id, name: me.username };
      if (G) E.addEvent(G, 'join', want);
    }
    return { out: { id: t.id, code: t.code }, extra: { forceHands: true } };
  });
}

async function leave(me: { id: string }, body: any) {
  return mutate(body.id, (t, G) => {
    const p = seatOf(t, me.id);
    if (p < 0) return { skip: true, ok: true };
    if (t.status === 'waiting') {
      t.seats[p] = null;
      if (t.host === me.id) {
        const other = t.seats.find((s) => s && !s.bot);
        if (other) t.host = other.uid!; else t.status = 'closed';
      }
    } else {
      t.seats[p] = { bot: true, was: me.id };
      if (G) E.addEvent(G, 'left', p);
      if (!humanCount(t)) t.status = 'closed';
      else if (t.host === me.id) t.host = t.seats.find((s) => s && !s.bot)!.uid!;
    }
    return { extra: { forceHands: true } };
  });
}

function newGameFor(t: Table) {
  t.seats = t.seats.map((s) => (s && !s.bot ? { uid: s.uid, name: s.name } : { bot: true, ...(s && s.was ? { was: s.was } : {}) }));
  const G = E.newGame({ target: t.target, level: t.level });
  E.startRound(G);
  t.status = 'playing';
  return G;
}
async function start(me: { id: string }, body: any) {
  return mutate(body.id, (t) => {
    if (t.host !== me.id) throw new Fail('المضيف بس يقدر يبدأ');
    if (t.status !== 'waiting' && t.status !== 'finished') throw new Fail('اللعب شغّال');
    return { G: newGameFor(t) };
  });
}

async function play(me: { id: string }, body: any) {
  return mutate(body.id, (t, G) => {
    if (!G || t.status !== 'playing') throw new Fail('ما فيه لعب شغّال');
    const p = seatOf(t, me.id);
    if (p < 0) throw new Fail('أنت مو جالس على الطاولة');
    if (body.reqId && G.req && G.req.id !== body.reqId) return { skip: true, ok: true, stale: true };
    try { E.act(G, body.kind === 'next' ? -1 : p, body.kind, body.v); }
    catch (_e) { throw new Fail('حركة غير مسموحة'); }
    if (t.seats[p]) t.seats[p]!.misses = 0;
  });
}

async function tick(_me: { id: string }, body: any) {
  return mutate(body.id, (t, G) => {
    if (!G || t.status !== 'playing' || !G.req || !G.deadline || Date.now() < G.deadline) return { skip: true, ok: true };
    const q = G.req;
    if (q.k === 'next') { E.act(G, -1, 'next', true); return; }
    const s = t.seats[q.p];
    E.act(G, q.p, q.k, E.botDecision(G, 'mid'));
    if (s && !s.bot) {
      s.misses = (s.misses || 0) + 1;
      if (s.misses >= MAX_MISSES) { t.seats[q.p] = { bot: true, was: s.uid }; E.addEvent(G, 'left', q.p); if (!humanCount(t)) t.status = 'closed'; return { extra: { forceHands: true } }; }
      E.addEvent(G, 'afk', q.p);
    }
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  try {
    const body = await req.json().catch(() => ({}));
    const action = body.action;
    if (action === 'signup') return json(await signup(body));
    const me = await userFrom(req);
    switch (action) {
      case 'create': return json(await create(me, body));
      case 'join': return json(await join(me, body));
      case 'leave': return json(await leave(me, body));
      case 'start': return json(await start(me, body));
      case 'play': return json(await play(me, body));
      case 'tick': return json(await tick(me, body));
      default: throw new Fail('طلب غير معروف');
    }
  } catch (e) {
    if (e instanceof Fail) return json({ error: e.message }, e.status);
    console.error(e);
    return json({ error: 'صار خطأ في السيرفر' }, 500);
  }
});
