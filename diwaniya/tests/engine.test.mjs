// Run: node --test diwaniya/tests/
import test from 'node:test';
import assert from 'node:assert/strict';
import * as E from '../engine/engine.js';

const rules = E.makeRules();
const hokmG = (trump, extra = {}) => ({ contract: { type: 'hokm', trump, buyer: 0 }, rules, locked: false, ...extra });
const sunG = (extra = {}) => ({ contract: { type: 'sun', buyer: 0 }, rules, locked: false, ...extra });

/* ---------- القيد ---------- */
test('sun conversion: 0-4 down, 5 exact, 6-9 up', () => {
  assert.equal(E.sunPoints(64), 12);
  assert.equal(E.sunPoints(65), 13);
  assert.equal(E.sunPoints(66), 14);
  assert.equal(E.sunPoints(130), 26);
  assert.equal(E.sunPoints(0), 0);
});
test('hokm conversion: 0-5 down, 6-9 up', () => {
  assert.equal(E.hokmPoints(85), 8);
  assert.equal(E.hokmPoints(86), 9);
  assert.equal(E.hokmPoints(162), 16);
});
test('deck has 32 cards, abnat totals 130 / 162', () => {
  assert.equal(E.FULL.length, 32);
  const s = E.FULL.reduce((a, c) => a + E.pts(sunG(), c), 0) + 10;
  const h = E.FULL.reduce((a, c) => a + E.pts(hokmG('H'), c), 0) + 10;
  assert.equal(s, 130); assert.equal(h, 162);
});

/* ---------- buyer result ---------- */
const base = { projects: { win: -1, points: [0, 0], abnat: [0, 0] }, baloot: null, rules, tricks: [4, 4] };
test('hokm: opponents at 82 → buyer fails, opponents take 16', () => {
  const r = E.scoreHand({ ...base, type: 'hokm', buyerTeam: 0, raw: [80, 82] });
  assert.equal(r.outcome, 'failed'); assert.deepEqual(r.fin, [0, 16]);
});
test('hokm: 81-81 is a tie and is split by default', () => {
  const r = E.scoreHand({ ...base, type: 'hokm', buyerTeam: 0, raw: [81, 81] });
  assert.equal(r.outcome, 'tie'); assert.equal(r.fin[0] + r.fin[1], 16);
});
test('tie rule buyer_loses', () => {
  const r = E.scoreHand({ ...base, type: 'hokm', buyerTeam: 0, raw: [81, 81], rules: E.makeRules({ tieRule: 'buyer_loses' }) });
  assert.equal(r.outcome, 'failed'); assert.deepEqual(r.fin, [0, 16]);
});
test('tie rule hang carries the buyer share to the next hand', () => {
  const R1 = E.makeRules({ tieRule: 'hang' });
  const r = E.scoreHand({ ...base, type: 'hokm', buyerTeam: 0, raw: [81, 81], rules: R1 });
  assert.equal(r.fin[0], 0); assert.equal(r.hangOut, 8);
  const r2 = E.scoreHand({ ...base, type: 'hokm', buyerTeam: 1, raw: [40, 122], rules: R1, hang: 8 });
  assert.equal(r2.fin[1], 12 + 8);
});
test('sun: buyer with opponents holding خمسين fails at 41, ties at 40', () => {
  const pr = { win: 1, points: [0, 10], abnat: [0, 50] };
  assert.equal(E.scoreHand({ ...base, type: 'sun', buyerTeam: 0, raw: [89, 41], projects: pr }).outcome, 'failed');
  assert.equal(E.scoreHand({ ...base, type: 'sun', buyerTeam: 0, raw: [90, 40], projects: pr }).outcome, 'tie');
});
test('buyer fails: opponents take all points and all counted projects', () => {
  const pr = { win: 0, points: [4, 0], abnat: [20, 0] };
  const r = E.scoreHand({ ...base, type: 'sun', buyerTeam: 0, raw: [40, 90], projects: pr });
  assert.equal(r.outcome, 'failed'); assert.deepEqual(r.fin, [0, 26 + 4]);
});
test('kaboot: 44 sun / 25 hokm plus own projects', () => {
  assert.deepEqual(E.scoreHand({ ...base, type: 'sun', buyerTeam: 0, raw: [130, 0], tricks: [8, 0] }).fin, [44, 0]);
  const pr = { win: 1, points: [5, 10], abnat: [50, 100] };
  assert.deepEqual(E.scoreHand({ ...base, type: 'hokm', buyerTeam: 0, raw: [162, 0], tricks: [8, 0], projects: pr }).fin, [25 + 5, 0]);
});
test('double: winner takes all ×2, projects ×2; ×3 does not multiply projects further', () => {
  const pr = { win: 0, points: [5, 0], abnat: [50, 0] };
  assert.deepEqual(E.scoreHand({ ...base, type: 'hokm', buyerTeam: 0, raw: [100, 62], projects: pr, mult: 2 }).fin, [32 + 10, 0]);
  assert.deepEqual(E.scoreHand({ ...base, type: 'hokm', buyerTeam: 0, raw: [100, 62], projects: pr, mult: 3 }).fin, [48 + 10, 0]);
});
test('double tie goes against the last caller', () => {
  const r = E.scoreHand({ ...base, type: 'hokm', buyerTeam: 0, raw: [81, 81], mult: 2, lastCaller: 1 });
  assert.deepEqual(r.fin, [32, 0]);
});
test('baloot adds 2 and is never multiplied', () => {
  const r = E.scoreHand({ ...base, type: 'hokm', buyerTeam: 0, raw: [100, 62], mult: 2, baloot: { p: 2 } });
  assert.deepEqual(r.fin, [34, 0]);
});

/* ---------- projects ---------- */
test('project detection and ranking', () => {
  const p = E.findProjects('sun', ['AS', 'AH', 'AC', 'AD', '7S', '8S', '9S', 'KH']);
  assert.equal(p[0].t, '400'); assert.equal(p[1].t, 'sira');
  assert.equal(E.findProjects('hokm', ['AS', 'AH', 'AC', 'AD'])[0].t, '100');
  const run = E.findProjects('sun', ['7H', '8H', '9H', 'TH', 'JH', 'QH']);
  assert.equal(run.length, 1); assert.equal(run[0].t, '100');            // a 6-run is one مية, not مية + سرا
  const eight = E.findProjects('sun', ['7H', '8H', '9H', 'TH', 'JH', 'QH', 'KH', 'AH']);
  assert.deepEqual(eight.map((x) => x.t), ['100', 'sira']);
  assert.equal(E.findProjects('sun', ['7H', '8H', 'TH', 'JH']).length, 0);
});

/* ---------- legal moves ---------- */
test('must follow suit', () => {
  const G = { ...sunG(), hands: [['AS', 'KH', '7H']], trick: [{ p: 3, c: 'TH' }] };
  assert.deepEqual(E.legal(G, 0).sort(), ['7H', 'KH']);
});
test('hokm: void must trump even when partner wins (default); free when rule off', () => {
  const G = { ...hokmG('S'), hands: [['7S', 'KC']], trick: [{ p: 2, c: 'AH' }, { p: 3, c: '7H' }] };
  assert.deepEqual(E.legal(G, 0), ['7S']);
  G.rules = E.makeRules({ mustTrumpWhenPartnerWins: false });
  assert.deepEqual(E.legal(G, 0).sort(), ['7S', 'KC']);
});
test('hokm: must over-trump; else under-trump by default', () => {
  const G = { ...hokmG('S'), hands: [['7S', 'AS', 'KC']], trick: [{ p: 1, c: 'AH' }, { p: 2, c: 'TS' }, { p: 3, c: '8H' }] };
  assert.deepEqual(E.legal(G, 0), ['AS']);
  G.hands = [['7S', 'KC']];
  assert.deepEqual(E.legal(G, 0), ['7S']);
  G.rules = E.makeRules({ mustUndertrump: false });
  assert.deepEqual(E.legal(G, 0).sort(), ['7S', 'KC']);
});
test('trump led: must play higher trump if possible', () => {
  const G = { ...hokmG('S'), hands: [['7S', 'JS', 'AH']], trick: [{ p: 3, c: '9S' }] };
  assert.deepEqual(E.legal(G, 0), ['JS']);
});
test('locked double: cannot lead trump unless only trumps', () => {
  const G = { ...hokmG('S', { locked: true }), hands: [['7S', 'AH']], trick: [] };
  assert.deepEqual(E.legal(G, 0), ['AH']);
  G.hands = [['7S', '8S']];
  assert.deepEqual(E.legal(G, 0).sort(), ['7S', '8S']);
});
test('trick winner: trump beats led suit; off-suit never wins', () => {
  const G = hokmG('S');
  assert.equal(E.winnerOf(G, [{ p: 0, c: 'AH' }, { p: 1, c: '7S' }, { p: 2, c: 'KH' }, { p: 3, c: 'AC' }]).p, 1);
  assert.equal(E.winnerOf(sunG(), [{ p: 0, c: '7H' }, { p: 1, c: 'AS' }, { p: 2, c: '8H' }, { p: 3, c: 'AC' }]).p, 2);
  assert.equal(E.winnerOf(G, [{ p: 0, c: 'AS' }, { p: 1, c: '9S' }, { p: 2, c: 'JS' }, { p: 3, c: 'TS' }]).p, 2);
});

/* ---------- state machine ---------- */
function seeded(seed) { let s = seed >>> 0; return () => ((s = (s * 1664525 + 1013904223) >>> 0) / 2 ** 32); }
test('wrong seat, wrong kind and illegal cards are rejected', () => {
  const G = E.newGame({ rnd: seeded(1), dealer: 3 }); E.startRound(G, seeded(2));
  assert.equal(G.req.p, 0);
  assert.throws(() => E.act(G, 1, 'bid', { t: 'pass' }));
  assert.throws(() => E.act(G, 0, 'card', 'AS'));
  assert.throws(() => E.act(G, 0, 'bid', { t: 'banana' }));
  E.act(G, 0, 'bid', { t: 'sun' });
  assert.equal(G.contract.type, 'sun');
});
test('أشكل: only 3rd/4th bidder in round 1; partner takes the face-up card', () => {
  const G = E.newGame({ rnd: seeded(3), dealer: 3 }); E.startRound(G, seeded(4));
  assert.ok(!G.req.d.opts.includes('ashkal'));
  E.act(G, 0, 'bid', { t: 'pass' }); E.act(G, 1, 'bid', { t: 'pass' });
  assert.ok(G.req.d.opts.includes('ashkal'));
  const flip = G.flip;
  E.act(G, 2, 'bid', { t: 'ashkal' });
  if (G.phase === 'double') { E.act(G, G.req.p, 'double', false); if (G.phase === 'double') E.act(G, G.req.p, 'double', false); }
  assert.equal(G.contract.type, 'sun'); assert.ok(G.hands[0].includes(flip));
});
test('doubling ladder دبل → ثري → فور → قهوة ends the match for the hand winner', () => {
  const G = E.newGame({ rnd: seeded(5), dealer: 3 }); E.startRound(G, seeded(6));
  E.act(G, 0, 'bid', { t: 'hokm' }); E.act(G, 1, 'bid', { t: 'pass' }); E.act(G, 2, 'bid', { t: 'pass' }); E.act(G, 3, 'bid', { t: 'pass' });
  assert.equal(G.phase, 'double'); assert.equal(G.req.p, 1);
  E.act(G, 1, 'double', true); assert.equal(G.req.p, 0); assert.equal(G.req.d.level, 3);
  E.act(G, 0, 'double', true); assert.equal(G.req.p, 1); assert.equal(G.req.d.level, 4);
  E.act(G, 1, 'double', true); assert.equal(G.req.p, 0); assert.equal(G.req.d.level, 5);
  E.act(G, 0, 'double', true);
  assert.equal(G.mult, 4); assert.ok(G.gahwa); assert.equal(G.phase, 'play');
  E.runBots(G, () => true);
  assert.ok(G.over); assert.ok(G.winner >= 0);
});
test('sun double only when buyer team > 100 and doubler ≤ 100', () => {
  const G = E.newGame({ rnd: seeded(7), dealer: 3 }); E.startRound(G, seeded(8));
  E.act(G, 0, 'bid', { t: 'sun' }); assert.equal(G.phase, 'play');
  const H = E.newGame({ rnd: seeded(7), dealer: 3 }); H.scores = [110, 90]; E.startRound(H, seeded(8));
  E.act(H, 0, 'bid', { t: 'sun' }); assert.equal(H.phase, 'double');
  E.act(H, 1, 'double', true); assert.equal(H.mult, 2); assert.equal(H.phase, 'play');
});
test('public view never contains hands, deck or unrevealed projects', () => {
  const G = E.newGame({ rnd: seeded(9) }); E.startRound(G, seeded(10));
  const v = JSON.stringify(E.publicView(G));
  assert.ok(!('hands' in E.publicView(G)) && !('deck' in E.publicView(G)));
  for (const c of G.hands[0]) assert.ok(!v.includes(`"${c}"`) || G.flip === c, 'hand card leaked: ' + c);
});
test('3000 full bot games: card conservation, score totals and termination', () => {
  let rounds = 0;
  for (let g = 0; g < 3000; g++) {
    const rnd = seeded(1000 + g);
    const R2 = E.makeRules({ tieRule: ['split', 'buyer_loses', 'hang'][g % 3], doubleLock: g % 2 ? 'locked' : 'open', mustTrumpWhenPartnerWins: g % 4 < 2 });
    const G = E.newGame({ rules: R2, rnd });
    E.startRound(G, rnd);
    for (let guard = 0; guard < 400 && !G.over; guard++) {
      E.runBots(G, () => true, ['easy', 'mid', 'hard'][g % 3], rnd);
      assert.equal(G.req.k, 'next');
      const s = G.summary; rounds++;
      assert.equal(G.played.length, 32); assert.equal(new Set(G.played).size, 32);
      assert.ok(G.hands.every((h) => h.length === 0));
      if (s.outcome !== 'kaboot' && s.outcome !== 'kaboot_against') assert.equal(G.raw[0] + G.raw[1], G.contract.type === 'sun' ? 130 : 162);
      assert.ok(s.fin[0] >= 0 && s.fin[1] >= 0);
      E.act(G, -1, 'next', true, rnd);
    }
    assert.ok(G.over, 'game finished');
    assert.ok(G.scores[G.winner] > G.scores[1 - G.winner] || G.gahwa);
  }
  assert.ok(rounds > 20000);
});
