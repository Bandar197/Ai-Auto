// Local UI smoke test: serves diwaniya/web, replaces the Supabase backend with an in-test fake,
// then opens every screen on phone and desktop sizes and fails on any JavaScript error.
// Run:  node diwaniya/tests/ui-smoke.mjs   (needs playwright and @supabase/supabase-js installed; see docs/TESTING.md)
import { createServer } from 'node:http';
import { readFile, mkdir } from 'node:fs/promises';
import { extname, join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';
import * as E from '../engine/engine.js';

const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_PATH || 'playwright');
const UMD = process.env.SUPABASE_UMD || require.resolve('@supabase/supabase-js/dist/umd/supabase.js');
const WEB = join(dirname(fileURLToPath(import.meta.url)), '..', 'web');
const SHOTS = process.env.SHOTS || '';
const SB = 'https://kdjexepmmkilhkjqflau.supabase.co';
const ME = '11111111-1111-4111-8111-111111111111';
const others = ['22222222-2222-4222-8222-222222222222', '33333333-3333-4333-8333-333333333333', '44444444-4444-4444-8444-444444444444'];

/* ---------- static server with SPA fallback (like GitHub Pages + 404.html) ---------- */
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png' };
const server = createServer(async (req, res) => {
  const p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  try { const b = await readFile(join(WEB, p)); res.writeHead(200, { 'Content-Type': TYPES[extname(p)] || 'application/octet-stream' }); res.end(b); }
  catch { res.writeHead(200, { 'Content-Type': 'text/html' }); res.end(await readFile(join(WEB, '404.html'))); }
});
await new Promise((ok) => server.listen(0, ok));
const BASE = `http://127.0.0.1:${server.address().port}`;

/* ---------- fixtures ---------- */
const profile = (id, n) => ({ id, username: 'player' + n, display_name: 'لاعب ' + n, avatar_url: null, rating: 1000 + n * 10, level: 3, xp: 400, games: 12, wins: 7, losses: 5,
  kaboots: 1, sun_rounds: 20, sun_won: 12, hokm_rounds: 15, hokm_won: 8, cur_streak: 2, best_streak: 4, bio: 'نبذة', player_no: 100000 + n, created_at: '2026-10-01T10:00:00Z',
  privacy_online: 'everyone', privacy_history: 'everyone', privacy_requests: 'everyone', privacy_invites: 'friends', equip_table: 'classic', equip_back: 'sadu', equip_frame: 'none', ranked_games: 3 });
const me = profile(ME, 1);
const card = (id, n) => ({ id, username: 'player' + n, display_name: 'لاعب ' + n, avatar_url: null, level: 2, rating: 1010, player_no: 100000 + n, frame: 'none', online: true });
const seats = [ME, ...others].map((u, i) => ({ uid: u, name: 'لاعب ' + (i + 1), ready: i % 2 === 0 }));
const G = E.newGame({ rnd: Math.random, dealer: 3 }); E.startRound(G);
const pub = { ...E.publicView(G), deadline: Date.now() + 30000, serverNow: Date.now() };
const rooms = {
  wait: { id: 'aaaaaaaa-0000-4000-8000-000000000001', code: 'wait01', kind: 'private', owner: ME, status: 'waiting', rules: E.makeRules({}), chat_mode: 'open', seats, members: [ME, ...others], match_id: null, state: null, version: 3, updated_at: new Date().toISOString() },
  play: { id: 'aaaaaaaa-0000-4000-8000-000000000002', code: 'play01', kind: 'friendly', owner: null, status: 'playing', rules: G.rules, chat_mode: 'quick', seats, members: [ME, ...others], match_id: 'bbbbbbbb-0000-4000-8000-000000000001', state: pub, version: 9, updated_at: new Date().toISOString() },
};
const roomById = (id) => Object.values(rooms).find((r) => r.id === id);
const history = [{ match_id: 'bbbbbbbb-0000-4000-8000-000000000009', ended_at: '2026-10-20T20:00:00Z', ranked: true, result: 'win', abandoned: false, us: 152, them: 98, rating_delta: 16, xp: 60 }];
const RPC = {
  touch: { unread: 2, banned: false, staff: null },
  lobby_stats: { online: 5, playing: 1, open_rooms: 1, queue_ranked: 0, queue_friendly: 2 },
  list_friends: [card(others[0], 2), { ...card(others[1], 3), online: false }],
  list_requests: { incoming: [{ id: 1, from: card(others[2], 4), at: '2026-10-22T10:00:00Z' }], outgoing: [] },
  my_notifications: [{ id: 1, kind: 'room_invite', data: { code: 'wait01', from: card(others[0], 2) }, at: new Date().toISOString(), read: false },
    { id: 2, kind: 'friend_request', data: { request_id: 1, from: card(others[2], 4) }, at: '2026-10-22T10:00:00Z', read: true }],
  player_history: history,
  my_progress: { challenges: [{ id: 1, title: 'العب ٣ مباريات', period: 'daily', target: 3, reward_xp: 40, progress: 1, done: false }],
    achievements: [{ code: 'first_win', name: 'أول فوز', description: 'افز بأول مباراة', icon: '🏆', xp: 50, unlocked: '2026-10-02T10:00:00Z' }],
    cosmetics: [{ code: 'classic', kind: 'table', name: 'كلاسيك', unlock: 'default', owned: true }] },
  get_profile: { ...me, is_me: true, friend: null, blocked: false, online: true, badges: [], season: null },
  leaderboard: [{ rank: 1, ...card(ME, 1), rating: 1200, games: 20, wins: 14 }],
  search_players: [card(others[1], 3)],
  quick_phrases: ['هلا والله'],
  username_available: true,
  match_detail: null,
  admin_overview: null,
};
const API = {
  bootstrap: { ok: true, role: null },
  room_join: (b) => { const r = Object.values(rooms).find((x) => x.code === b.code); return r ? [200, { id: r.id, code: r.code }] : [404, { error: 'room_not_found' }]; },
  queue_poll: { queued: false },
};

async function fakeBackend(route) {
  const req = route.request(), url = new URL(req.url()), path = url.pathname;
  const json = (status, body) => route.fulfill({ status, contentType: 'application/json', headers: { 'access-control-allow-origin': '*' }, body: JSON.stringify(body) });
  if (req.method() === 'OPTIONS') return route.fulfill({ status: 200, headers: { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*', 'access-control-allow-methods': '*' } });
  if (path.startsWith('/auth/v1/user')) return json(200, { id: ME, email: 'me@example.com', user_metadata: {} });
  if (path.startsWith('/auth/v1/')) return json(200, {});
  if (path === '/functions/v1/api') {
    const b = JSON.parse(req.postData() || '{}'); const h = API[b.action];
    if (typeof h === 'function') { const [s, body] = h(b); return json(s, body); }
    return json(200, h || { ok: true });
  }
  if (path.startsWith('/rest/v1/rpc/')) { const fn = path.split('/').pop(); return json(200, RPC[fn] ?? null); }
  if (path.startsWith('/rest/v1/')) {
    const table = path.split('/').pop(); const single = (req.headers()['accept'] || '').includes('vnd.pgrst.object');
    let rows = [];
    if (table === 'profiles') rows = [me, ...others.map((u, i) => profile(u, i + 2))].filter((p) => { const f = url.searchParams.get('id'); return !f || f.includes(p.id) || f === 'eq.' + p.id; });
    if (table === 'rooms') { const f = url.searchParams.get('id'); rows = f ? [roomById(f.replace('eq.', ''))].filter(Boolean) : [rooms.wait]; }
    if (table === 'room_hands') rows = [{ seat: 0, user_id: ME, cards: G.hands[0] }];
    return json(200, single ? rows[0] || null : rows);
  }
  if (path.startsWith('/storage/')) return json(200, {});
  return json(404, {});
}

/* ---------- run ---------- */
const browser = await chromium.launch(process.env.CHROMIUM ? { executablePath: process.env.CHROMIUM } : {});
const failures = [];
const PAGES_GUEST = ['/login', '/signup', '/forgot', '/rules', '/training', '/u/player2', '/does-not-exist'];
const PAGES_USER = ['/', '/play', '/u/player1', '/settings', '/friends', '/leaderboard', '/notifications', '/room/wait01', '/room/play01', '/training', '/rules', '/admin'];
async function visit(signedIn, viewport, label) {
  const ctx = await browser.newContext({ viewport, locale: 'ar-SA', reducedMotion: 'reduce' });
  await ctx.route('https://cdn.jsdelivr.net/**', async (r) => r.fulfill({ contentType: 'text/javascript', body: await readFile(UMD, 'utf8') }));
  await ctx.route('https://fonts.googleapis.com/**', (r) => r.fulfill({ contentType: 'text/css', body: '' }));
  await ctx.route('https://fonts.gstatic.com/**', (r) => r.abort());
  await ctx.route(SB + '/**', fakeBackend);
  await ctx.routeWebSocket(/supabase\.co/, (ws) => ws.close());
  if (signedIn) {
    const session = { access_token: 'x.' + Buffer.from(JSON.stringify({ sub: ME, exp: 4102444800 })).toString('base64url') + '.y', token_type: 'bearer', expires_in: 3600, expires_at: 4102444800,
      refresh_token: 'r', user: { id: ME, email: 'me@example.com', user_metadata: {}, app_metadata: {}, aud: 'authenticated' } };
    await ctx.addInitScript((s) => { localStorage.setItem('sb-kdjexepmmkilhkjqflau-auth-token', s); localStorage.setItem('diwaniya.policy.v1', '1'); }, JSON.stringify(session));
  }
  const page = await ctx.newPage();
  const errs = [];
  page.on('pageerror', (e) => errs.push(String(e)));
  page.on('console', (m) => { if (m.type() === 'error' && !/WebSocket|Failed to load resource|net::ERR/.test(m.text())) errs.push(m.text()); });
  for (const p of signedIn ? PAGES_USER : PAGES_GUEST) {
    errs.length = 0;
    await page.goto(BASE + p, { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(900);
    const text = (await page.locator('#main').innerText().catch(() => '')).trim();
    const overflow = await page.evaluate(() => document.documentElement.scrollWidth - innerWidth);
    const rtl = await page.evaluate(() => document.documentElement.dir);
    if (errs.length) failures.push(`${label} ${p}: ${errs.join(' | ')}`);
    if (!text) failures.push(`${label} ${p}: empty page`);
    if (overflow > 2) failures.push(`${label} ${p}: horizontal overflow ${overflow}px`);
    if (rtl !== 'rtl') failures.push(`${label} ${p}: dir=${rtl}`);
    if (SHOTS) { await mkdir(SHOTS, { recursive: true }); await page.screenshot({ path: join(SHOTS, `${label}${p.replace(/\//g, '_') || '_home'}.png`) }); }
    console.log(`${errs.length ? '✗' : '✓'} ${label} ${p} — ${text.slice(0, 50).replace(/\s+/g, ' ')}`);
  }
  // training: play real cards against bots on this screen size
  if (!signedIn) {
    await page.goto(BASE + '/training', { waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(600);
    const start = page.locator('a[href^="/training/"], button').filter({ hasText: /العب|ابدأ|تدريب/ }).first();
    if (await start.count()) { await start.click(); await page.waitForTimeout(1200); }
    let played = 0;
    for (let i = 0; i < 80 && played < 6; i++) {
      const choice = page.locator('.bidbar button, .actions-bar button, [data-bid], [data-act]').first();
      const legal = page.locator('.hand .pc.legal, .hand .pc:not(.illegal):not([aria-disabled="true"])').first();
      if (await legal.count() && await legal.isVisible()) { await legal.click().catch(() => {}); played++; }
      else if (await choice.count() && await choice.isVisible()) await choice.click().catch(() => {});
      await page.waitForTimeout(350);
    }
    console.log(`  ${label} training: clicked ${played} cards`);
    if (played < 1) failures.push(`${label} training: could not play a card`);
    if (errs.length) failures.push(`${label} training: ${errs.join(' | ')}`);
  }
  await ctx.close();
}
for (const [label, vp] of [['phone', { width: 390, height: 844 }], ['desktop', { width: 1366, height: 820 }]]) {
  await visit(false, vp, label + '-guest');
  await visit(true, vp, label + '-user');
}
await browser.close(); server.close();
if (failures.length) { console.error('\nFAILURES:\n' + failures.join('\n')); process.exit(1); }
console.log('\nUI smoke test passed.');
