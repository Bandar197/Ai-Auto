/* Film 1 – the job seeker: «قدمت.. وبعدين؟»   (72 s, 120 BPM grid: 1 beat = 0.5 s) */
(function () {
  const { tl, $, $$, add, scene, enter, to, pop, out, reveal, onFrame, prog, win, clamp, lerp, rng, flash, streaks, particles, dust, cue } = E;
  const ic = UI.ic;
  const line = (parent, cls, text, top, extra = '') => add(parent, `<div class="c ${cls}" style="left:40px;width:1000px;top:${top}px;${extra}">${text}</div>`);

  /* ══════════ SCENE 1 · HOOK (0 – 10) ══════════ */
  (function S1() {
    const sc = scene('s1', 0, 10), w = sc.world;
    const clock = { v: 0 };                       // local time that decelerates and freezes at 4.9
    tl.to(clock, { v: 4.6, duration: 4.6, ease: 'none' }, 0).to(clock, { v: 4.72, duration: 0.3, ease: 'power2.out' }, 4.6);
    const FREEZE = 4.9;

    sc.root.insertBefore(E.el(`<div class="floor"></div>`), sc.drift);   // outside the sorted 3D context
    const dim = add(w, `<div class="c" style="left:-3000px;top:-3000px;width:7000px;height:8000px;background:#020c0e"></div>`);
    gsap.set(dim, { z: -140, opacity: 0 });

    /* clutter: job pages, CVs and e-mails piling up around him */
    const spots = [[-40, 330, -520, 'job', -8], [800, 300, -640, 'cv', 7], [60, 760, -380, 'mail', 6], [820, 720, -300, 'job', -5], [-150, 1130, -260, 'cv', -9], [900, 1100, -420, 'mail', 8],
      [330, 120, -900, 'job', 3], [620, 60, -1100, 'mail', -4], [-260, 620, -900, 'job', 5], [1080, 520, -1000, 'cv', -6], [150, 520, -1300, 'mail', 2], [700, 500, -1400, 'job', -3],
      [-330, 240, -1500, 'cv', 9], [1150, 180, -1600, 'job', -8], [420, 380, -1800, 'cv', 4], [-190, 1460, 260, 'job', -12], [960, 1500, 300, 'mail', 10], [540, 900, -2000, 'job', 0],
      [-420, 900, -1700, 'mail', 6], [1300, 880, -1500, 'cv', -5]];
    const fl = spots.map(([x, y, z, kind, rot], i) => {
      const e = add(w, UI.win(kind, kind === 'cv' ? 230 : 280, kind === 'cv' ? 290 : 230));
      const blur = z > 0 ? 9 : z < -1200 ? 4 : z < -700 ? 2 : 0;
      if (blur) e.style.filter = `blur(${blur}px)`;
      return { e, x, y, z, rot, at: 0.5 + i * 0.19, ph: i * 1.7 };
    });

    /* application form + the button */
    const form = add(w, `<div class="panel c" style="width:640px;height:400px;padding:38px 42px">
      <div class="row"><div class="ico" style="color:#9af7ee">${ic.brief}</div><div class="col" style="gap:6px"><div class="ttl">طلب توظيف</div><div class="sub">نموذج التقديم</div></div></div>
      <div class="col" style="gap:14px;margin-top:30px"><div class="sk" style="width:92%"></div><div class="sk" style="width:64%"></div></div>
      <div class="btn" style="position:absolute;left:42px;right:42px;bottom:38px;font-size:46px"><span style="width:46px;height:46px;display:inline-block">${ic.send}</span><span>إرسال الطلب</span></div>
      <div class="sheen"><i></i></div></div>`);
    gsap.set(form, { x: 220, y: 300, z: -160 });
    const btn = $('.btn', form);
    const cur = add(w, `<div class="cursor">${ic.cursor}</div>`);

    /* flying applications */
    const clicks = [0.35, 1.0, 1.5, 1.9, 2.2, 2.45, 2.65, 2.82, 2.97, 3.1];
    for (let t = 3.21; t < 4.62; t += 0.105) clicks.push(+t.toFixed(3));
    const r = rng(42);
    const cards = clicks.map((L, i) => {
      const e = add(w, `<div class="paper c" style="width:120px;height:150px;padding:14px;box-shadow:0 0 30px rgba(46,230,214,.55),0 20px 40px rgba(0,0,0,.4)"><div class="sk t" style="width:70%;height:10px"></div><div class="col" style="gap:8px;margin-top:14px"><div class="sk" style="height:7px"></div><div class="sk" style="height:7px;width:80%"></div><div class="sk" style="height:7px;width:60%"></div></div><div style="position:absolute;left:14px;bottom:12px;width:30px;height:30px;color:#1b7f88">${ic.send}</div></div>`);
      const side = i % 2 ? 1 : -1;
      const a = (-90 + side * (18 + r() * 68)) * Math.PI / 180;
      return { e, L, a, d: 520 + r() * 520, zz: -500 - r() * 1300, spin: (r() - 0.5) * 120, tiltY: (r() - 0.5) * 100 };
    });
    clicks.forEach((c, i) => cue(c, 'click', i < 3 ? 1 : 0.7));

    /* counter */
    const cnt = add(w, `<div class="c" style="left:0;width:1080px;top:84px;text-align:center"><div class="lbl" style="font-size:34px">طلبات مرسلة</div><div class="num" style="font-size:168px;line-height:1.1;color:#fff;text-shadow:0 0 50px rgba(46,230,214,.5)"></div></div>`);
    const cntNum = $('.num', cnt);
    const keys = [[0.34, 0], [0.35, 1], [2.5, 10], [3.25, 50], [4.0, 100], [9, 100]];
    const countAt = (c) => { for (let i = 1; i < keys.length; i++) if (c <= keys[i][0]) { const [a, va] = keys[i - 1], [b, vb] = keys[i]; return Math.round(lerp(va, vb, Math.pow(clamp((c - a) / (b - a)), 1.6))); } return 100; };
    enter(cnt, { opacity: 0, y: -40 }, { opacity: 1, y: 0 }, 0.8, 0.5);
    [2.5, 3.25, 4.0].forEach((t, i) => {
      tl.fromTo(cntNum, { scale: 1.42, color: '#ffe7a8' }, { scale: 1, color: '#ffffff', duration: 0.5, ease: 'power3.out', immediateRender: false }, t);
      cue(t, 'pop', 0.8 + i * 0.15);
    });

    /* desk, character, laptop */
    const desk = add(w, `<div class="c" style="left:-400px;top:1700px;width:1880px;height:500px;background:linear-gradient(180deg,#143034 0%,#081416 22%,#050809 100%);border-top:2px solid rgba(125,243,232,.4);box-shadow:0 -24px 90px rgba(46,230,214,.14)"></div>`);
    gsap.set(desk, { z: 10 });
    const ch = Char.bust({ variant: 'seeker' }); w.appendChild(ch.el);
    gsap.set(ch.el, { x: 165, y: 640, scale: 1.25, transformOrigin: '0 0' });
    const lap = Char.laptop(); w.appendChild(lap.el);
    gsap.set(lap.el, { x: 176, y: 1250, scale: 1.3, transformOrigin: '0 0', z: 20 });
    const S = ch.s;
    Object.assign(S, { furrow: 0.45, lookY: 0.75, glow: 0.75, flick: 1, smile: -0.1 });
    tl.to(S, { brow: -0.55, furrow: 0.1, smile: -0.35, tilt: 2.5, duration: 2, ease: 'sine.inOut' }, 2.4)
      .to(S, { eye: 1.3, brow: 0.9, lookY: 0, furrow: 0, flick: 0, tilt: 0, open: 0.35, duration: 0.25, ease: 'power3.out' }, 4.7)
      .to(S, { eye: 1, brow: -0.85, lookX: 0.55, lookY: -0.55, tilt: -5, turn: 0.35, smile: -0.45, open: 0, duration: 0.9, ease: 'power2.inOut' }, 5.5)
      .to(S, { lookX: -0.4, turn: -0.25, tilt: 3, duration: 1.1, ease: 'sine.inOut' }, 7.0)
      .to(S, { lookX: 0, lookY: -1, turn: 0, tilt: 0, brow: 0.7, eye: 1.25, open: 0.25, duration: 0.4, ease: 'power3.out' }, 8.75);

    /* the question */
    const q1 = line(w, 'h2 glowtxt', 'تدري أصلا..', 330), q2 = line(w, 'h2 glowtxt', 'سيرتك مناسبة للوظيفة؟', 428, 'font-size:72px');
    reveal(q1, 6.0); reveal(q2, 6.75, { stagger: 0.42 });
    out([q1, q2], 8.45, 0.35, { y: -40 });
    out(cnt, 8.35, 0.4, { y: -60 });
    const qm = add(w, `<div class="c" style="left:0;width:1080px;top:60px;text-align:center"><div class="gold" style="font:800 1040px/1.1 'Alexandria'">؟</div></div>`);
    gsap.set(qm, { z: -120, transformOrigin: '50% 55%' });
    enter(qm, { scale: 0.15, opacity: 0, rotation: -25 }, { scale: 1, opacity: 1, rotation: 0 }, 8.55, 0.45, 'back.out(1.5)');
    tl.to(qm, { scale: 1.08, duration: 1.0, ease: 'sine.inOut' }, 9.0);
    tl.fromTo(sc.shake, { v: 34 }, { v: 0, duration: 0.6, ease: 'power2.out', immediateRender: false }, 8.95);
    flash(8.95, { color: '255,225,150', y: 700, a: 0.75 });
    cue(8.95, 'impact', 1);

    /* freeze: world dims, the form drops back */
    tl.to(dim, { opacity: 0.62, duration: 0.5, ease: 'power2.out' }, FREEZE - 0.2);
    tl.to(form, { opacity: 0, z: -600, duration: 0.7, ease: 'power2.in' }, 5.1);
    tl.to(cur, { opacity: 0, duration: 0.2 }, 4.75);
    cue(4.45, 'freeze', 1);

    /* camera: macro on the button → snap back → slow push → whip up */
    gsap.set(w, { transformOrigin: '540px 630px', scale: 2.45 });
    tl.to(w, { scale: 1, duration: 1.0, ease: 'expo.out' }, 0.42);
    gsap.set(sc.cam, { transformOrigin: '540px 1050px' });
    tl.to(sc.cam, { scale: 1.09, duration: 4.5, ease: 'sine.inOut' }, 4.9);
    tl.to(sc.cam, { y: 3000, duration: 0.45, ease: 'power3.in' }, 9.55);
    cue(0, 'hit', 1); cue(0.4, 'whoosh', 0.8); cue(9.5, 'whoosh', 1);
    streaks(9.5, 10.35, { vertical: true, n: 34, seed: 5 });
    flash(0.35, { x: 540, y: 630, r: 900, a: 0.55, dur: 0.4 });

    onFrame((t) => {
      if (t >= 10) return;
      const c = clock.v;
      ch.update(t);
      cntNum.textContent = (c >= 4.0 ? '+' : '') + countAt(c);
      /* button press + cursor */
      let last = -9; for (const k of clicks) if (k <= t) last = k;
      const press = Math.exp(-(t - last) * 16);
      btn.style.transform = `scale(${(1 - press * 0.07).toFixed(4)})`;
      btn.style.filter = `brightness(${(1 + press * 0.6).toFixed(3)})`;
      cur.style.transform = `translate3d(${(640 + Math.sin(c * 3) * 6).toFixed(1)}px,${(628 + press * 8).toFixed(1)}px,-150px) scale(${(1.05 - press * 0.16).toFixed(3)})`;
      /* ripples on the front canvas (button is the camera anchor, so screen position is fixed) */
      const ctx = E.front;
      for (const k of clicks) {
        const u = (t - k) / 0.55; if (u < 0 || u > 1) continue;
        const sca = t < 1.4 ? lerp(2.45, 1, prog(t, 0.42, 1.42, 'expo.out')) : 1;
        ctx.strokeStyle = `rgba(160,255,245,${(1 - u) * 0.8})`; ctx.lineWidth = 5 * (1 - u) + 1;
        ctx.beginPath(); ctx.ellipse(540, 630, (120 + u * 330) * sca, (50 + u * 150) * sca, 0, 0, 6.2832); ctx.stroke();
      }
      /* flying applications */
      for (const k of cards) {
        const u = (c - k.L) / 1.9;
        if (u <= 0) { k.e.style.opacity = 0; continue; }
        const e = 1 - Math.pow(1 - clamp(u), 2.4);
        const x = 480 + Math.cos(k.a) * k.d * e, y = 540 + Math.sin(k.a) * k.d * e + 160 * e * e;
        const z = lerp(-150, k.zz, e);
        k.e.style.opacity = clamp(u * 9) * (1 - clamp((u - 0.72) / 0.28));
        k.e.style.transform = `translate3d(${x.toFixed(1)}px,${y.toFixed(1)}px,${z.toFixed(1)}px) rotateZ(${(k.spin * e).toFixed(1)}deg) rotateY(${(k.tiltY * e).toFixed(1)}deg) scale(${(0.5 + e * 0.6).toFixed(3)})`;
      }
      /* clutter drift */
      const dimF = 1 - prog(t, FREEZE, FREEZE + 0.5) * 0.55;
      for (const f of fl) {
        const p = prog(c, f.at, f.at + 0.7, 'back.out(1.5)');
        const dx = Math.sin(c * 0.9 + f.ph) * 34, dy = Math.cos(c * 0.7 + f.ph * 1.3) * 26;
        f.e.style.opacity = clamp(p * 1.4) * (f.z > 0 ? dimF * 0.9 : 1);
        f.e.style.transform = `translate3d(${(f.x + dx).toFixed(1)}px,${(f.y + dy + (1 - p) * 160).toFixed(1)}px,${f.z}px) rotateZ(${(f.rot + Math.sin(c + f.ph) * 3).toFixed(2)}deg) rotateY(${(Math.sin(c * 0.6 + f.ph) * 16).toFixed(2)}deg) scale(${(0.5 + p * 0.5).toFixed(3)})`;
      }
    });
  })();


  /* ══════════ SCENE 2 · THE MAZE (10 – 20) ══════════
   * The maze is projected by hand onto the back canvas (extruded neon walls), so depth is exact
   * and the walls can shatter into the particles that later build the platform. */
  const HUB = { x: 140, y: 330, w: 800, h: 1040 };          // where the platform panel forms in scene 3
  (function S2() {
    const sc = scene('s2', 10, 20), w = sc.world;
    const COLS = 7, ROWS = 11, CELL = 220, WH = 78, P = 1500, CX = 540, CY = 1340;
    const r = rng(23), id = (c, q) => q * COLS + c;
    const adj = Array.from({ length: COLS * ROWS }, () => []), seen = new Array(COLS * ROWS).fill(false);
    (function carve(c, q) {
      seen[id(c, q)] = true;
      const dirs = [[1, 0], [-1, 0], [0, 1], [0, -1]];
      for (let i = 3; i > 0; i--) { const j = Math.floor(r() * (i + 1)); [dirs[i], dirs[j]] = [dirs[j], dirs[i]]; }
      for (const [dx, dy] of dirs) { const nc = c + dx, nq = q + dy; if (nc < 0 || nq < 0 || nc >= COLS || nq >= ROWS || seen[id(nc, nq)]) continue; adj[id(c, q)].push(id(nc, nq)); adj[id(nc, nq)].push(id(c, q)); carve(nc, nq); }
    })(3, 8);
    const X0 = -COLS * CELL / 2, Y0 = -ROWS * CELL / 2;
    const cen = (i) => ({ u: X0 + (i % COLS + 0.5) * CELL, v: Y0 + (Math.floor(i / COLS) + 0.5) * CELL });
    const walls = [];
    for (let q = 0; q < ROWS; q++) for (let c = 0; c < COLS; c++) {
      const x = X0 + c * CELL, y = Y0 + q * CELL, i = id(c, q);
      if (q === 0) walls.push([x, y, x + CELL, y]);
      if (c === 0) walls.push([x, y, x, y + CELL]);
      if (c === COLS - 1 || !adj[i].includes(id(c + 1, q))) walls.push([x + CELL, y, x + CELL, y + CELL]);
      if (q === ROWS - 1 || !adj[i].includes(id(c, q + 1))) walls.push([x, y + CELL, x + CELL, y + CELL]);
    }
    const wr = rng(5); const wx = walls.map(() => ({ a: wr() * 6.28, d: 200 + wr() * 700, s: 0.6 + wr() }));
    /* the walk: depth-first wandering with backtracking, pausing at dead ends */
    const START = id(3, 8), walk = [START];
    (function go(i, from) { for (const n of [...adj[i]].reverse()) { if (n === from || walk.length > 26) continue; walk.push(n); go(n, i); if (walk.length > 26) return; walk.push(i); } })(START, -1);
    const deadIdx = []; walk.forEach((c, i) => { if (i && adj[c].length === 1 && c !== START) deadIdx.push(i); });
    const lastDead = deadIdx.length ? deadIdx[deadIdx.length - 1] : walk.length - 1; walk.length = lastDead + 1;
    const T0 = 10.55, T1 = 16.9, DW = 0.55, nDead = deadIdx.length - 1;
    const stepT = (T1 - T0 - nDead * DW) / (walk.length - 1);
    const arrive = [T0]; for (let i = 1; i < walk.length; i++) arrive.push(arrive[i - 1] + stepT + (deadIdx.includes(i - 1) ? DW : 0));
    const pos = (t) => {
      if (t <= T0) return { ...cen(walk[0]), dir: 1 };
      for (let i = 1; i < walk.length; i++) if (t < arrive[i]) {
        const a = cen(walk[i - 1]), b = cen(walk[i]); const k = clamp((t - (arrive[i] - stepT)) / stepT); const e = k * k * (3 - 2 * k);
        return { u: lerp(a.u, b.u, e), v: lerp(a.v, b.v, e), dir: b.u < a.u ? -1 : b.u > a.u ? 1 : 0, moving: k > 0 && k < 1 };
      }
      return { ...cen(walk[walk.length - 1]), dir: 0 };
    };
    const cam = { s: 2.6, th: 18, mix: 0, a: 0 };
    tl.to(cam, { s: 1.12, th: 51, duration: 1.2, ease: 'expo.out' }, 10).to(cam, { a: 1, duration: 0.35, ease: 'none' }, 10)
      .to(cam, { s: 0.5, th: 40, mix: 1, duration: 1.6, ease: 'power2.inOut' }, 16.95);
    let C = null;
    const proj = (u, v, h) => {
      const X = (u - C.tx) * C.s, Y = (v - C.ty) * C.s, Z = h * C.s;
      const y3 = Y * C.cos - Z * C.sin, z3 = Math.min(P - 80, Y * C.sin + Z * C.cos), k = P / (P - z3);
      return { x: CX + X * k, y: CY + y3 * k, k: k * C.s, z: z3 };
    };

    /* DOM actors: walker + site windows at every dead end */
    const deads = []; for (let i = 0; i < COLS * ROWS; i++) if (adj[i].length === 1 && i !== START) deads.push(i);
    const sites = deads.map((cell, n) => {
      const e = add(w, UI.win(n % 3 === 1 ? 'mail' : 'job', 230, 190));
      const chip = add(e, `<div class="chip solid" style="position:absolute;left:50%;top:58px;font-size:26px;padding:6px 18px;white-space:nowrap;box-shadow:0 6px 18px rgba(0,0,0,.35)"></div>`);
      const hit = deadIdx.find((i) => walk[i] === cell);
      return { e, chip, cell, t: hit !== undefined ? arrive[hit] : null };
    });
    sites.forEach((s) => { if (s.t) { cue(s.t + 0.05, 'click', 0.8); cue(s.t + 0.42, 'swish', 0.5); } });
    const wk = Char.walker(); w.appendChild(wk.el);

    const bub = (txt, x, y, at, rot) => {
      const b = add(w, `<div class="c panel dark" style="border-radius:40px;padding:22px 44px;border-color:rgba(244,201,93,.55);box-shadow:0 24px 60px rgba(0,0,0,.6),0 0 50px rgba(244,201,93,.16)"><div class="h3" style="white-space:nowrap;font-size:52px">${txt}</div></div>`);
      gsap.set(b, { x, y, rotation: rot, transformOrigin: '50% 50%', zIndex: 6000 });
      pop(b, at, 0.55); tl.to(b, { y: y - 16, duration: 1.3, ease: 'sine.inOut', repeat: 5, yoyo: true }, at + 0.55);
      cue(at, 'pop', 0.9);
      return b;
    };
    const bubs = [bub('وين أقدم؟', 560, 250, 12.0, 4), bub('هل سيرتي مناسبة؟', 70, 470, 14.0, -4), bub('وش صار على طلبي؟', 330, 700, 16.0, 3)];
    tl.to(bubs, { scale: 1.5, opacity: 0, duration: 0.3, ease: 'power2.in' }, 18.5);
    cue(16.5, 'riser', 1, { dur: 2 }); cue(18.5, 'impact', 1); cue(18.6, 'sparkle', 1);
    flash(18.5, { color: '190,255,250', y: 1000, a: 1, dur: 0.7 });
    flash(10.0, { color: '170,255,245', a: 0.55, dur: 0.5 });
    tl.fromTo(sc.shake, { v: 30 }, { v: 0, duration: 0.6, ease: 'power2.out', immediateRender: false }, 18.5);

    /* particles: maze fragments → outline of the platform panel (crosses into scene 3) */
    const pr = rng(9);
    particles({ n: 1500, seed: 77, t0: 18.5, t1: 21.1, spread: 0.3, swirl: 420, size: 3.2, gold: 0.22, fadeIn: 0.15, hold: 0.1, fadeOut: 0.5, ease: 'power3.inOut',
      from: (i, q) => ({ x: 80 + q() * 920, y: 420 + Math.pow(q(), 0.7) * 1250 }),
      to: (i, q) => { const per = q() * 2 * (HUB.w + HUB.h); let x, y;
        if (per < HUB.w) { x = HUB.x + per; y = HUB.y; } else if (per < HUB.w + HUB.h) { x = HUB.x + HUB.w; y = HUB.y + per - HUB.w; }
        else if (per < 2 * HUB.w + HUB.h) { x = HUB.x + per - HUB.w - HUB.h; y = HUB.y + HUB.h; } else { x = HUB.x; y = HUB.y + per - 2 * HUB.w - HUB.h; }
        return q() < 0.3 ? { x: HUB.x + q() * HUB.w, y: HUB.y + q() * HUB.h } : { x, y }; } });

    onFrame((t) => {
      if (t < 10 || t >= 20) return;
      const p = pos(t), mid = { u: 0, v: 330 };
      const lagp = pos(t - 0.18);
      C = { tx: lerp(lagp.u, mid.u, cam.mix), ty: lerp(lagp.v, mid.v, cam.mix), s: cam.s, cos: Math.cos(cam.th * Math.PI / 180), sin: Math.sin(cam.th * Math.PI / 180) };
      const ctx = E.back, boom = prog(t, 18.5, 19.4, 'power2.out'), A = cam.a * (1 - prog(t, 18.5, 19.3));
      if (A > 0.001) {
        /* floor glow under the walker */
        const g0 = proj(p.u, p.v, 0);
        const gl = ctx.createRadialGradient(g0.x, g0.y, 0, g0.x, g0.y, 420 * g0.k);
        gl.addColorStop(0, `rgba(46,230,214,${0.22 * A})`); gl.addColorStop(1, 'rgba(46,230,214,0)');
        ctx.fillStyle = gl; ctx.fillRect(0, 0, 1080, 1920);
        /* job pins on every cell once the camera pulls back: hundreds of scattered openings */
        const pinA = prog(t, 17.1, 18.2);
        if (pinA > 0) for (let i = 0; i < COLS * ROWS; i++) {
          const c = cen(i), q = proj(c.u, c.v, 40), on = clamp(pinA * 3 - (Math.hypot(c.u - p.u, c.v - p.v) / 1500) * 2);
          if (on <= 0) continue;
          const pulse = 0.6 + 0.4 * Math.sin(t * 6 + i);
          ctx.fillStyle = `rgba(244,201,93,${0.85 * on * A * pulse})`; ctx.beginPath(); ctx.arc(q.x, q.y, 9 * q.k * on, 0, 6.2832); ctx.fill();
          ctx.fillStyle = `rgba(244,201,93,${0.16 * on * A})`; ctx.beginPath(); ctx.arc(q.x, q.y, 30 * q.k, 0, 6.2832); ctx.fill();
        }
        /* extruded walls, far → near */
        const quads = walls.map((s, i) => {
          const o = wx[i], ox = Math.cos(o.a) * o.d * boom, oy = Math.sin(o.a) * o.d * boom, lift = boom * 300 * o.s;
          const a = proj(s[0] + ox, s[1] + oy, lift), b = proj(s[2] + ox, s[3] + oy, lift), c = proj(s[2] + ox, s[3] + oy, WH + lift), d = proj(s[0] + ox, s[1] + oy, WH + lift);
          return { a, b, c, d, z: (a.z + b.z) / 2 };
        }).sort((m, n) => m.z - n.z);
        for (const q of quads) {
          if (q.a.z > P - 200 || q.b.z > P - 200) continue;
          const fog = clamp(1 + q.z / 2600, 0.12, 1) * A;
          ctx.fillStyle = `rgba(18,120,122,${0.5 * fog})`;
          ctx.beginPath(); ctx.moveTo(q.a.x, q.a.y); ctx.lineTo(q.b.x, q.b.y); ctx.lineTo(q.c.x, q.c.y); ctx.lineTo(q.d.x, q.d.y); ctx.closePath(); ctx.fill();
          ctx.strokeStyle = `rgba(46,230,214,${0.22 * fog})`; ctx.lineWidth = 12 * q.c.k; ctx.lineCap = 'round';
          ctx.beginPath(); ctx.moveTo(q.d.x, q.d.y); ctx.lineTo(q.c.x, q.c.y); ctx.stroke();
          ctx.strokeStyle = `rgba(160,255,246,${0.95 * fog})`; ctx.lineWidth = Math.max(1, 3.4 * q.c.k);
          ctx.beginPath(); ctx.moveTo(q.d.x, q.d.y); ctx.lineTo(q.c.x, q.c.y); ctx.stroke();
          ctx.strokeStyle = `rgba(46,230,214,${0.35 * fog})`; ctx.lineWidth = Math.max(1, 1.6 * q.a.k);
          ctx.beginPath(); ctx.moveTo(q.a.x, q.a.y); ctx.lineTo(q.b.x, q.b.y); ctx.stroke();
        }
      }
      /* site windows */
      const gone = 1 - prog(t, 18.5, 18.8);
      for (const s of sites) {
        const c = cen(s.cell), q = proj(c.u, c.v, 232), k = q.k * 0.92, me = proj(p.u, p.v, 0);
        const vis = q.y > -200 && q.y < 2300 && q.z < P - 300;
        s.e.style.display = vis ? 'block' : 'none'; if (!vis) continue;
        const near = s.t ? prog(t, s.t - 0.25, s.t + 0.1, 'back.out(2)') : 0;
        const kk = k * (1 + near * 0.18);
        s.e.style.zIndex = Math.round(2000 + q.z);
        s.e.style.opacity = cam.a * gone * clamp(1.15 + q.z / 2400, 0.25, 1) * (1 - clamp((q.z - me.z - 260) / 200) * (1 - cam.mix));
        s.e.style.transform = `translate(${(q.x - 115 * kk).toFixed(1)}px,${(q.y - 190 * kk).toFixed(1)}px) scale(${kk.toFixed(4)})`;
        s.e.style.transformOrigin = '0 0';
        if (s.t && t > s.t) { const wait = t > s.t + 0.42; s.chip.style.display = 'inline-flex'; s.chip.textContent = wait ? 'بانتظار الرد..' : 'تم الإرسال';
          s.chip.className = 'chip ' + (wait ? 'gold-c' : 'solid'); s.chip.style.background = wait ? '#3a2c0a' : ''; 
          s.chip.style.transform = `translateX(-50%) scale(${(prog(t, s.t, s.t + 0.25, 'back.out(2.5)') * 1.25).toFixed(3)})`; }
        else s.chip.style.display = 'none';
      }
      /* walker */
      const q = proj(p.u, p.v, 0), k = q.k * 1.5;
      const look = p.dir || (Math.sin(t * 5) > 0 ? 1 : -1);
      wk.el.style.zIndex = Math.round(2000 + q.z + 40);
      wk.el.style.opacity = cam.a * gone;
      wk.el.style.transformOrigin = '0 0';
      wk.el.style.transform = `translate(${(q.x - 55 * k * look).toFixed(1)}px,${(q.y - 184 * k).toFixed(1)}px) scale(${(k * look).toFixed(4)},${k.toFixed(4)})`;
      wk.body.setAttribute('transform', `translate(0 ${(p.moving ? -Math.abs(Math.sin(t * 15)) * 9 : 0).toFixed(2)}) rotate(${(p.moving ? Math.sin(t * 15) * 4 : Math.sin(t * 5) * 3).toFixed(2)} 55 180)`);
    });
  })();


  /* ══════════ SCENE 3 · THE SMART ANSWER (20 – 32) ══════════ */
  const JOBS = [
    { title: 'محلل بيانات', sub: 'شركة تقنية · الرياض · عبر المنصة', pct: 0.92 },
    { title: 'أخصائي تسويق رقمي', sub: 'جدة · من موقع الشركة', pct: 0.84, gold: true },
    { title: 'مدير مشاريع', sub: 'شركة استشارات · الرياض · عبر المنصة', pct: 0.77 },
    { title: 'مصمم تجربة مستخدم', sub: 'الدمام · من موقع الشركة', pct: 0.63, gold: true },
    { title: 'محاسب أول', sub: 'مجموعة تجارية · الخبر · عبر المنصة', pct: 0.48 },
  ];
  (function S3() {
    const sc = scene('s3', 20, 32), w = sc.world;
    sc.root.insertBefore(E.el(`<div class="floor" style="opacity:.6"></div>`), sc.drift);
    const hub = add(w, `<div class="panel c p3d" style="width:${HUB.w}px;height:${HUB.h}px">
      <div class="row" style="position:absolute;left:40px;right:40px;top:34px;justify-content:space-between">
        <div class="row"><div class="ico" style="color:#9af7ee">${ic.brief}</div><div class="ttl" style="font-size:42px">الوظائف</div></div>
        <div class="row" style="gap:12px"><span class="chip solid">${'<span style="width:26px;height:26px;display:inline-block">' + ic.spark + '</span>'}المنصة</span><span class="chip gold-c">مواقع الشركات</span></div>
      </div>
      <div class="glowline" style="left:40px;right:40px;top:140px"></div>
      <div class="sheen"><i></i></div></div>`);
    gsap.set(hub, { x: HUB.x, y: HUB.y });
    enter(hub, { opacity: 0, scale: 0.94 }, { opacity: 1, scale: 1 }, 20.55, 0.7, 'power2.out');
    tl.fromTo($('.sheen i', hub), { left: '-40%' }, { left: '120%', duration: 1.1, ease: 'power2.inOut', immediateRender: false }, 21.0);
    flash(21.1, { color: '150,255,245', y: 850, a: 0.5, dur: 0.6 }); cue(21.05, 'ding', 0.9); cue(20.0, 'swish', 0.6);

    const cards = JOBS.map((j, i) => {
      const e = add(hub, UI.jobCard({ ...j, style: 'width:720px;height:150px' }));
      const fromR = !j.gold;
      enter(e, { x: 40 + (fromR ? 760 : -760), y: 172 + i * 168, z: 420, rotationY: fromR ? -55 : 55, opacity: 0 }, { x: 40, z: 30, rotationY: 0, opacity: 1 }, 21.35 + i * 0.4, 0.75, 'power3.out');
      cue(21.35 + i * 0.4, 'swish', 0.6);
      const ringEl = $('.ring', e); gsap.set(ringEl, { opacity: 0 });
      tl.to(ringEl, { opacity: 1, duration: 0.3 }, 27.2 + i * 0.22);
      return { e, ring: ringEl, pct: j.pct };
    });

    const h1 = line(w, 'h2 glowtxt', 'كل الوظائف.. في مكان واحد', 170);
    reveal(h1, 21.0); out(h1, 24.35, 0.35, { y: -30 });
    const h2 = line(w, 'h2 glowtxt', 'ويحلل سيرتك الذاتية', 170);
    reveal(h2, 24.9); out(h2, 26.95, 0.3, { y: -30 });
    const h3 = line(w, 'h2 glowtxt', 'ويوضح توافقك مع كل فرصة', 170);
    reveal(h3, 27.25, { stagger: 0.3 }); out(h3, 31.5, 0.3, { y: -30 });

    /* CV + scan */
    const cv = add(w, UI.cv(360, 480, `<div style="position:absolute;inset:0;overflow:hidden;border-radius:18px"><div class="scan" style="top:-100px"></div></div>`));
    enter(cv, { x: -460, y: 900, z: 200, rotationY: 50, rotation: -14, opacity: 0 }, { x: 34, y: 760, rotationY: 18, rotation: -4, opacity: 1 }, 24.4, 0.8, 'power3.out');
    cue(24.4, 'whoosh', 0.6);
    tl.to(hub, { x: HUB.x + 70, rotationY: -13, z: -90, duration: 0.9, ease: 'power3.inOut' }, 24.3);
    const scan = $('.scan', cv);
    tl.fromTo(scan, { top: -100 }, { top: 480, duration: 0.75, ease: 'sine.inOut', immediateRender: false }, 25.0)
      .fromTo(scan, { top: 480 }, { top: -100, duration: 0.75, ease: 'sine.inOut', immediateRender: false }, 25.75);
    cue(25.0, 'scan', 0.8, { dur: 1.5 });
    const skills = ['تحليل البيانات', 'خبرة 3 سنوات', 'Excel · SQL'].map((txt, i) => {
      const c = add(w, `<span class="chip solid c" style="font-size:30px;padding:10px 24px;box-shadow:0 0 34px rgba(46,230,214,.6)">${txt}</span>`);
      enter(c, { x: 150, y: 870 + i * 96, z: 230, scale: 0, opacity: 0 }, { x: 330, scale: 1, opacity: 1 }, 25.45 + i * 0.3, 0.45, 'back.out(2)');
      cue(25.45 + i * 0.3, 'pop', 0.6);
      tl.to(c, { x: 760, y: 560 + i * 168, z: 60, scale: 0.5, opacity: 0, duration: 0.55, ease: 'power3.in' }, 26.6 + i * 0.14);
      return c;
    });
    tl.to(cv, { x: -480, rotationY: 60, opacity: 0, duration: 0.6, ease: 'power3.in' }, 27.0);
    tl.to(hub, { x: HUB.x, rotationY: 0, z: 0, duration: 0.8, ease: 'power3.inOut' }, 26.9);
    cards.forEach((c, i) => cue(27.25 + i * 0.22, 'tick', 0.5));

    /* hero match ring */
    const hero = add(w, `<div class="panel gold-edge c" style="width:660px;height:800px;text-align:center">
      <div class="lbl" style="margin-top:54px;font-size:38px;color:#cfe">نسبة المطابقة</div>
      <div style="position:relative;width:440px;height:440px;margin:26px auto 0">
        <svg viewBox="0 0 104 104" style="position:absolute;inset:0;transform:rotate(-90deg)"><circle cx="52" cy="52" r="44" fill="none" stroke="rgba(255,255,255,.1)" stroke-width="7"/>
          <circle class="arc" cx="52" cy="52" r="44" fill="none" stroke="#f4c95d" stroke-width="7" stroke-linecap="round" stroke-dasharray="${UI.RC.toFixed(2)}" style="filter:drop-shadow(0 0 5px #f4c95d)"/></svg>
        <div class="num gold v" style="position:absolute;inset:0;display:grid;place-items:center;font-size:128px"></div></div>
      <div class="ttl" style="margin-top:26px;font-size:46px">محلل بيانات</div>
      <div class="sub" style="font-size:30px;margin-top:4px">مهاراتك وخبرتك تناسب هذي الفرصة</div>
      <div style="margin-top:22px"><span class="tag-ex">مثال توضيحي</span></div><div class="sheen"><i></i></div></div>`);
    const heroP = { v: 0 };
    enter(hero, { x: 210, y: 420, z: 600, scale: 0.3, opacity: 0, rotationY: -40 }, { z: 260, scale: 1, opacity: 1, rotationY: 0 }, 28.6, 0.7, 'back.out(1.4)');
    cue(28.6, 'whoosh', 0.7); cue(28.9, 'riser', 0.9, { dur: 1.1 });
    tl.to(heroP, { v: 0.92, duration: 1.1, ease: 'power2.out' }, 28.9);
    tl.to(hub, { z: -260, opacity: 0.45, duration: 0.7, ease: 'power2.inOut' }, 28.55);
    tl.fromTo(hero, { scale: 1.09 }, { scale: 1, duration: 0.6, ease: 'power3.out', immediateRender: false }, 30.0);
    tl.fromTo($('.sheen i', hero), { left: '-40%' }, { left: '120%', duration: 1.0, ease: 'power2.inOut', immediateRender: false }, 30.05);
    flash(30.0, { color: '255,225,150', y: 800, a: 0.7 }); cue(30.0, 'impact', 1); cue(30.05, 'sparkle', 0.9);
    tl.fromTo(sc.shake, { v: 22 }, { v: 0, duration: 0.5, ease: 'power2.out', immediateRender: false }, 30.0);
    particles({ n: 260, seed: 31, t0: 30.0, t1: 31.6, spread: 0.2, swirl: 120, size: 3, gold: 0.75, fadeIn: 0.05, fadeOut: 0.4, ease: 'power3.out',
      from: () => ({ x: 540, y: 800 }), to: (i, q) => { const a = q() * 6.28, d = 350 + q() * 500; return { x: 540 + Math.cos(a) * d, y: 800 + Math.sin(a) * d * 1.2 }; } });

    /* character */
    const ch = Char.bust({ variant: 'seeker', seed: 0.4 }); w.appendChild(ch.el);
    enter(ch.el, { x: 285, y: 1900, z: 120, scale: 0.85, transformOrigin: '0 0' }, { y: 1300 }, 20.9, 0.9, 'power3.out');
    const S = ch.s; Object.assign(S, { lookY: -0.9, brow: 0.5, glow: 0.55, smile: 0, eye: 1.1 });
    tl.to(S, { smile: 0.35, brow: 0.3, duration: 1.2, ease: 'sine.inOut' }, 22.2)
      .to(S, { lookX: 0.7, turn: 0.4, lookY: -0.5, tilt: 3, duration: 0.6, ease: 'power2.inOut' }, 24.5)
      .to(S, { lookX: 0, turn: 0, lookY: -0.9, tilt: 0, duration: 0.6, ease: 'power2.inOut' }, 27.0)
      .to(S, { brow: 1, eye: 1.3, open: 0.5, smile: 0.5, duration: 0.3, ease: 'power3.out' }, 29.9)
      .to(S, { open: 0, smile: 1, eye: 1.05, brow: 0.5, duration: 0.6, ease: 'power2.inOut' }, 30.6);

    /* camera: slow orbit, then everything lifts away into the feature tour */
    gsap.set(sc.cam, { transformOrigin: '540px 900px' });
    enter(sc.cam, { rotationY: 9, scale: 0.94 }, { rotationY: -6, scale: 1.03 }, 20, 11.5, 'sine.inOut');
    tl.to([hero, hub], { y: '-=1900', opacity: 0, duration: 0.5, ease: 'power3.in' }, 31.5);
    cue(31.45, 'whoosh', 0.9); streaks(31.4, 32.3, { vertical: true, n: 26, seed: 8 });

    onFrame((t) => {
      if (t < 20 || t >= 32) return;
      ch.update(t);
      cards.forEach((c, i) => UI.setRing(c.ring, c.pct * prog(t, 27.25 + i * 0.22, 28.2 + i * 0.22, 'power2.out')));
      hero.querySelector('.arc').setAttribute('stroke-dashoffset', (UI.RC * (1 - heroP.v)).toFixed(2));
      hero.querySelector('.v').textContent = Math.round(heroP.v * 100) + '%';
    });
  })();


  /* ══════════ SCENE 4 · FEATURE TOUR (32 – 58) ══════════
   * One continuous stage: the same character reacts below while the interface morphs above him. */
  (function S4() {
    const sc = scene('s4', 32, 58), w = sc.world;
    sc.root.insertBefore(E.el(`<div class="floor" style="opacity:.6"></div>`), sc.drift);
    const F = [32, 36, 40, 43, 47, 51, 54.5, 58];
    const TITLES = ['بحث ذكي يرتب فرصك حسب المطابقة', 'حلل سيرتك.. قوتها وفرص تحسينها', 'احفظ الوظائف وتابع الفرص الجديدة', 'قدم على عدة وظائف وتابع طلباتك',
      'تقديم تلقائي بالذكاء الاصطناعي', 'تابع المراحل وتواصل مع المنشأة', 'مساعد ذكي يوجهك ويطور فرصك'];
    const NOTES = [null, null, null, null, 'وفق حدود الخدمة', 'عند إتاحة هذه المزايا', null];
    const steps = add(w, `<div class="c row" style="left:0;width:1080px;top:104px;justify-content:center;gap:14px">${TITLES.map(() => '<div class="bar-bg" style="width:112px;height:10px"><i></i></div>').join('')}</div>`);
    const stepBars = $$('i', steps);
    enter(steps, { opacity: 0 }, { opacity: 1 }, 32.1, 0.4); out(steps, 57.6, 0.3);
    const groups = TITLES.map((title, i) => {
      const a = F[i], b = F[i + 1];
      const g = add(w, `<div class="c p3d" style="width:960px;height:900px"></div>`);
      enter(g, { x: -1100, y: 400, z: -380, rotationY: 62, opacity: 0 }, { x: 60, z: 0, rotationY: 0, opacity: 1 }, a - 0.05, 0.65, 'expo.out');
      tl.to(g, { x: 1240, z: -380, rotationY: -62, opacity: 0, duration: 0.42, ease: 'power3.in' }, b - 0.4);
      const h = line(w, 'h2 glowtxt', title, 160, 'font-size:56px');
      reveal(h, a + 0.12, { stagger: 0.07, dur: 0.5 }); out(h, b - 0.38, 0.3, { y: -24 });
      if (NOTES[i]) { const n = add(w, `<div class="c" style="left:0;width:1080px;top:262px;text-align:center"><span class="tag-ex" style="font-size:26px;padding:9px 22px">${NOTES[i]}</span></div>`); enter(n, { opacity: 0, y: 12 }, { opacity: 1, y: 0 }, a + 0.7, 0.4); out(n, b - 0.38, 0.3); }
      cue(a - 0.1, 'whoosh', 0.55);
      return g;
    });
    const hooks = [];
    const row = (g, j, y, extra = '') => add(g, UI.jobCard({ ...j, style: `width:900px;height:140px;${extra}` }));

    /* ── F1 · smart search, sorted by match ── */
    (function () {
      const g = groups[0], a = F[0];
      const bar = add(g, `<div class="panel c" style="width:900px;height:112px;border-radius:56px;display:flex;align-items:center;gap:22px;padding:0 40px"><div style="width:50px;height:50px;color:#7df3e8">${ic.search}</div><div class="ttl q" style="font-size:42px"></div></div>`);
      gsap.set(bar, { x: 30, y: 0, z: 40 });
      UI.type($('.q', bar), 'محلل بيانات', a + 0.45, a + 1.2);
      for (let k = 0; k < 6; k++) cue(a + 0.45 + k * 0.125, 'type', 0.5);
      const chips = ['الرياض', 'دوام كامل', 'حسب المطابقة'].map((c, i) => {
        const e = add(g, `<span class="chip c ${i === 2 ? 'solid' : ''}" style="font-size:30px;padding:10px 26px">${i === 2 ? '<span style="width:28px;height:28px;display:inline-block">' + ic.spark + '</span>' : ''}${c}</span>`);
        gsap.set(e, { x: [700, 440, 60][i], y: 134, z: 40 });
        pop(e, i === 2 ? a + 1.95 : a + 1.25 + i * 0.12, 0.45);
        return e;
      });
      cue(a + 1.95, 'pop', 0.8);
      const order = [3, 0, 4, 1];                      // shown unsorted first
      const sorted = [...order].sort((m, n) => JOBS[n].pct - JOBS[m].pct);
      const cards = order.map((ji, i) => {
        const e = row(g, JOBS[ji]);
        enter(e, { x: 30, y: 222 + i * 164 + 60, z: 0, opacity: 0 }, { y: 222 + i * 164, opacity: 1 }, a + 1.2 + i * 0.09, 0.5);
        const rank = sorted.indexOf(ji);
        tl.to(e, { y: 222 + rank * 164, z: rank === 0 ? 70 : 0, duration: 0.75, ease: 'back.inOut(1.4)' }, a + 2.2 + (3 - rank) * 0.06);
        UI.setRing($('.ring', e), JOBS[ji].pct);
        if (rank === 0) { tl.to(e, { borderColor: 'rgba(244,201,93,.9)', boxShadow: '0 22px 60px rgba(0,0,0,.5), 0 0 60px rgba(244,201,93,.4)', duration: 0.4 }, a + 2.95); }
        return e;
      });
      cue(a + 2.2, 'swish', 0.9);
      const best = add(g, `<span class="chip gold-c c" style="font-size:28px;background:#3a2c0a">الأنسب لك</span>`);
      gsap.set(best, { x: 150, y: 198, z: 110 }); pop(best, a + 3.0, 0.45); cue(a + 3.0, 'ding', 0.8);
    })();

    /* ── F2 · CV analysis ── */
    (function () {
      const g = groups[1], a = F[1];
      const cv = add(g, UI.cv(420, 620, `<div style="position:absolute;inset:0;overflow:hidden;border-radius:18px"><div class="scan" style="top:-100px"></div></div>`));
      gsap.set(cv, { x: 500, y: 10, z: 30, rotationY: -10 });
      tl.fromTo($('.scan', cv), { top: -100 }, { top: 620, duration: 1.0, ease: 'sine.inOut', immediateRender: false }, a + 0.5)
        .fromTo($('.scan', cv), { top: 620 }, { top: -100, duration: 0.9, ease: 'sine.inOut', immediateRender: false }, a + 1.5);
      cue(a + 0.5, 'scan', 0.8, { dur: 1.9 });
      const hd = (txt, y, col, at) => { const e = add(g, `<div class="c ttl" style="font-size:36px;color:${col}">${txt}</div>`); gsap.set(e, { x: 30, y }); enter(e, { opacity: 0, x: 0 }, { opacity: 1, x: 30 }, at, 0.4); e.style.width = '440px'; };
      hd('نقاط القوة', 20, '#a8f5cf', a + 0.8); hd('فرص التحسين', 350, '#ffe7a8', a + 1.75);
      [['خبرة عملية مناسبة', 90, 'green-c', 0.95], ['مهارات تحليل قوية', 170, 'green-c', 1.2], ['شهادات مهنية', 250, 'green-c', 1.45], ['أضف إنجازات بالأرقام', 420, 'gold-c', 1.95], ['أبرز مشاريعك العملية', 500, 'gold-c', 2.2]].forEach(([txt, y, cls, d]) => {
        const e = add(g, `<span class="chip ${cls} c" style="font-size:30px;padding:10px 24px">${txt}</span>`);
        e.style.right = '500px'; e.style.left = 'auto';
        gsap.set(e, { y, z: 60, transformOrigin: '100% 50%' }); pop(e, a + d, 0.42); cue(a + d, 'pop', 0.55);
      });
      const sp = add(g, `<div class="panel c" style="width:900px;height:170px;padding:28px 40px"><div class="row" style="justify-content:space-between"><div class="ttl" style="font-size:36px">قوة السيرة الذاتية</div><div class="row"><span class="tag-ex">مثال توضيحي</span><div class="num sv" style="font-size:56px;color:#ffe7a8"></div></div></div><div class="bar-bg g" style="margin-top:22px;height:22px"><i></i></div></div>`);
      enter(sp, { x: 30, y: 760, z: 30, opacity: 0 }, { y: 680, opacity: 1 }, a + 1.9, 0.5);
      const sv = { v: 0.58 }; tl.to(sv, { v: 0.86, duration: 1.1, ease: 'power2.inOut' }, a + 2.5); cue(a + 2.5, 'riser', 0.6, { dur: 1.1 }); cue(a + 3.6, 'ding', 0.8);
      const fill = $('.bar-bg i', sp), num = $('.sv', sp);
      hooks.push(() => { fill.style.transform = `scaleX(${sv.v.toFixed(4)})`; num.textContent = Math.round(sv.v * 100) + '%'; });
    })();

    /* ── F3 · saved jobs + alerts ── */
    (function () {
      const g = groups[2], a = F[2];
      const card = row(g, JOBS[0]); gsap.set(card, { x: 30, y: 30, z: 40 }); UI.setRing($('.ring', card), 0.92);
      const bm = add(g, `<div class="c" style="width:96px;height:96px;border-radius:26px;background:#0c3b41;border:2px solid rgba(244,201,93,.5);display:grid;place-items:center;color:#f4c95d"><div style="width:54px;height:54px" class="bmi">${ic.mark}</div></div>`);
      gsap.set(bm, { x: 20, y: 200, z: 60 });
      const bmPath = $('path', bm);
      tl.to(bmPath, { attr: { fill: '#f4c95d' }, duration: 0.15 }, a + 0.62);
      tl.fromTo(bm, { scale: 1.45 }, { scale: 1, duration: 0.5, ease: 'back.out(2)', immediateRender: false }, a + 0.62);
      cue(a + 0.6, 'click', 1); cue(a + 0.66, 'pop', 0.7);
      const lbl = add(g, `<div class="c ttl" style="font-size:36px;width:700px">احفظها.. وارجع لها أي وقت</div>`); gsap.set(lbl, { x: 140, y: 222 }); enter(lbl, { opacity: 0 }, { opacity: 1 }, a + 0.3, 0.4);
      const saved = add(g, `<div class="panel c" style="width:430px;height:400px;padding:30px"><div class="row" style="justify-content:space-between"><div class="ttl" style="font-size:36px">المحفوظة</div><div class="num sc" style="font-size:50px;color:#ffe7a8"></div></div>
        <div class="col" style="gap:16px;margin-top:22px">${[0, 1, 2].map(() => '<div class="kpi row" style="padding:16px 20px"><div style="width:36px;height:36px;color:#f4c95d">' + ic.mark + '</div><div class="col" style="gap:8px;flex:1"><div class="sk t" style="width:70%"></div><div class="sk" style="width:45%"></div></div></div>').join('')}</div></div>`);
      gsap.set(saved, { x: 500, y: 360, z: 20 });
      const items = $$('.kpi', saved); enter(items[2], { opacity: 0, x: 80 }, { opacity: 1, x: 0 }, a + 1.05, 0.45, 'back.out(1.6)'); cue(a + 1.0, 'swish', 0.6);
      const ghost = add(g, `<div class="c" style="width:900px;height:140px;border-radius:28px;border:2px solid #f4c95d;box-shadow:0 0 40px rgba(244,201,93,.5)"></div>`);
      enter(ghost, { x: 30, y: 30, z: 50, opacity: 0, scale: 1 }, { opacity: 0.9 }, a + 0.62, 0.1);
      tl.to(ghost, { x: 310, y: 610, scale: 0.4, opacity: 0, duration: 0.5, ease: 'power3.in' }, a + 0.72);
      const bell = add(g, `<div class="panel c" style="width:430px;height:400px;display:grid;place-items:center"><div class="bl" style="width:190px;height:190px;color:#7df3e8;filter:drop-shadow(0 0 24px rgba(46,230,214,.7))">${ic.bell}</div>
        <div class="num bd" style="position:absolute;left:130px;top:70px;width:74px;height:74px;border-radius:50%;background:#ff6b6b;color:#fff;font-size:40px;display:grid;place-items:center;box-shadow:0 0 24px rgba(255,107,107,.7)">1</div>
        <div class="sub" style="position:absolute;bottom:34px;left:0;right:0;text-align:center;font-size:30px">إشعارات الفرص الجديدة</div></div>`);
      gsap.set(bell, { x: 30, y: 360, z: 20 });
      const bl = $('.bl', bell), bd = $('.bd', bell); gsap.set(bl, { transformOrigin: '50% 8%' }); gsap.set(bd, { scale: 0 });
      tl.to(bd, { scale: 1, duration: 0.4, ease: 'back.out(3)' }, a + 1.5); cue(a + 1.45, 'bell', 1);
      const toast = (txt, y, at) => { const e = add(g, `<div class="panel gold-edge c row" style="width:560px;height:104px;padding:0 28px;border-radius:26px"><div style="width:44px;height:44px;color:#f4c95d">${ic.spark}</div><div class="ttl" style="font-size:32px">${txt}</div></div>`);
        enter(e, { x: -420, y, z: 160, opacity: 0, rotationY: 30 }, { x: -30, opacity: 1, rotationY: 0 }, at, 0.5, 'back.out(1.5)'); cue(at, 'ding', 0.8); return e; };
      toast('وظيفة جديدة تناسبك', 790, a + 1.75); toast('فرصة جديدة في الرياض', 680, a + 2.2);
      const sn = $('.sc', saved);
      hooks.push((t) => { bl.style.transform = `rotate(${(Math.sin((t - a - 1.45) * 22) * 16 * Math.exp(-Math.max(0, t - a - 1.45) * 2.2) * (t > a + 1.45 ? 1 : 0)).toFixed(2)}deg)`; sn.textContent = t > a + 1.2 ? '3' : '2'; bd.textContent = t > a + 2.2 ? '2' : '1'; });
    })();

    /* ── F4 · apply to several jobs + track ── */
    (function () {
      const g = groups[3], a = F[3];
      const rows = [0, 2, 1].map((ji, i) => {
        const e = row(g, { ...JOBS[ji], ring: false }); gsap.set(e, { x: 30, y: 10 + i * 160, z: 20 });
        const box = add(e, `<div style="width:64px;height:64px;border-radius:18px;border:3px solid rgba(125,243,232,.6);display:grid;place-items:center;flex:none"><div class="tk" style="width:64px;height:64px;border-radius:16px;background:#2ee6d6;color:#04282c;display:grid;place-items:center"><div style="width:40px;height:40px">${ic.check}</div></div></div>`);
        const tk = $('.tk', box); gsap.set(tk, { scale: 0 });
        tl.to(tk, { scale: 1, duration: 0.3, ease: 'back.out(3)' }, a + 0.4 + i * 0.22); cue(a + 0.4 + i * 0.22, 'click', 0.8);
        const st = add(e, `<span class="chip green-c" style="position:absolute;left:28px;font-size:28px;background:#0c3a2a">تم التقديم</span>`); gsap.set(st, { scale: 0 });
        tl.to(box, { opacity: 0, duration: 0.2 }, a + 1.45 + i * 0.14).to(st, { scale: 1, duration: 0.4, ease: 'back.out(2.4)' }, a + 1.5 + i * 0.14);
        cue(a + 1.5 + i * 0.14, 'pop', 0.6);
        return { e, st };
      });
      const btn = add(g, `<div class="btn c" style="width:900px;font-size:42px"><span style="width:44px;height:44px;display:inline-block">${ic.send}</span><span class="bt">تقديم على 3 وظائف</span></div>`);
      gsap.set(btn, { x: 30, y: 500, z: 50 });
      tl.to(btn, { scale: 0.94, duration: 0.08, ease: 'power2.in' }, a + 1.22).to(btn, { scale: 1, duration: 0.4, ease: 'back.out(3)' }, a + 1.3);
      cue(a + 1.25, 'click', 1); cue(a + 1.3, 'swish', 0.8);
      const track = add(g, `<div class="panel c" style="width:900px;height:250px;padding:26px 36px"><div class="row" style="justify-content:space-between"><div class="ttl" style="font-size:36px">متابعة طلباتي</div><span class="chip">3 طلبات نشطة</span></div>
        <div class="row" style="margin-top:26px;gap:0;justify-content:space-between">${['تم التقديم', 'قيد المراجعة', 'مقابلة', 'القرار'].map((s2, i) => `<div class="col" style="align-items:center;gap:12px;width:200px"><div class="nd" style="width:46px;height:46px;border-radius:50%;background:#16383d;border:3px solid rgba(125,243,232,.5)"></div><div class="sub" style="font-size:27px">${s2}</div></div>`).join('')}</div>
        <div class="bar-bg" style="position:absolute;left:136px;right:136px;top:139px;height:6px;z-index:-1"><i></i></div></div>`);
      enter(track, { x: 30, y: 720, z: 20, opacity: 0 }, { y: 640, opacity: 1 }, a + 1.6, 0.5);
      const pv = { v: 0 }; tl.to(pv, { v: 0.36, duration: 0.8, ease: 'power2.inOut' }, a + 2.2); cue(a + 2.6, 'ding', 0.7);
      tl.to(rows[0].st, { scale: 0, duration: 0.15 }, a + 2.55).set(rows[0].st, { innerText: 'قيد المراجعة', className: 'chip gold-c', background: '#3a2c0a' }, a + 2.7).to(rows[0].st, { scale: 1, duration: 0.4, ease: 'back.out(2.4)' }, a + 2.7);
      const nds = $$('.nd', track), fill = $('.bar-bg i', track), bt = $('.bt', btn);
      hooks.push((t) => { fill.style.transform = `scaleX(${pv.v.toFixed(4)})`; nds.forEach((n, i) => { const on = pv.v >= i / 3 - 0.02 && t > a + 2.0; n.style.background = on ? '#2ee6d6' : '#16383d'; n.style.boxShadow = on ? '0 0 22px rgba(46,230,214,.8)' : 'none'; });
        bt.textContent = t > a + 1.3 ? 'تم إرسال 3 طلبات' : 'تقديم على 3 وظائف'; });
    })();

    /* ── F5 · AI auto-apply within the plan limits ── */
    (function () {
      const g = groups[4], a = F[4];
      const top = add(g, `<div class="panel c row" style="width:900px;height:150px;padding:0 40px;justify-content:space-between"><div class="row"><div class="ico" style="color:#9af7ee">${ic.spark}</div><div class="col"><div class="ttl" style="font-size:40px">التقديم التلقائي</div><div class="sub">يقدم عنك على الفرص المناسبة</div></div></div><div class="toggle"><i></i></div></div>`);
      gsap.set(top, { x: 30, y: 0, z: 30 });
      const tg = $('.toggle', top), knob = $('.toggle i', top);
      tl.to(knob, { x: 62, backgroundColor: '#ffffff', duration: 0.3, ease: 'back.out(2)' }, a + 0.6).to(tg, { backgroundColor: '#2ee6d6', boxShadow: '0 0 34px rgba(46,230,214,.7)', duration: 0.3 }, a + 0.6);
      cue(a + 0.6, 'click', 1); cue(a + 0.7, 'sparkle', 0.8);
      const orb = add(g, `<div class="orb c"></div>`); gsap.set(orb, { x: 150, y: 190, z: 90 });
      enter(orb, { scale: 0, opacity: 0 }, { scale: 1, opacity: 1 }, a + 0.7, 0.6, 'back.out(1.8)');
      const sent = [0, 1, 2].map((i) => {
        const e = add(g, `<div class="panel c" style="width:400px;height:170px;padding:24px 28px;border-radius:26px"><div class="ttl" style="font-size:30px">${JOBS[[0, 2, 1][i]].title}</div><div class="col" style="gap:12px;margin-top:16px"><div class="bar-bg" style="height:12px"><i></i></div><div class="bar-bg" style="height:12px;width:70%"><i></i></div></div><div class="ck" style="position:absolute;left:22px;top:22px">${UI.check(48)}</div></div>`);
        const at = a + 1.15 + i * 0.7, x = [500, 30, 500][i], y = [410, 500, 610][i];
        enter(e, { x: 100, y: 230, z: 60, scale: 0.2, opacity: 0 }, { x, y, z: 30, scale: 1, opacity: 1 }, at, 0.5, 'power3.out');
        const bars = $$('.bar-bg i', e), ck = $('.ck', e); gsap.set(bars, { scaleX: 0 }); gsap.set(ck, { scale: 0 });
        tl.to(bars, { scaleX: 1, duration: 0.35, stagger: 0.1, ease: 'power2.out' }, at + 0.25).to(ck, { scale: 1, duration: 0.3, ease: 'back.out(3)' }, at + 0.6);
        cue(at, 'swish', 0.6); cue(at + 0.6, 'ding', 0.6 + i * 0.1);
        return e;
      });
      const lim = add(g, `<div class="panel dark c row" style="width:900px;height:110px;padding:0 36px;justify-content:space-between;border-radius:28px"><div class="ttl" style="font-size:32px">ضمن حدود باقتك</div><div class="row" style="gap:10px">${[0, 1, 2, 3, 4].map(() => '<div class="sg" style="width:74px;height:18px;border-radius:9px;background:rgba(255,255,255,.12)"></div>').join('')}<div class="num lv" style="font-size:40px;color:#fff;margin-right:12px"></div></div></div>`);
      enter(lim, { x: 30, y: 800, z: 40, opacity: 0 }, { y: 860 - 110 + 60, opacity: 1 }, a + 0.9, 0.5);
      const sg = $$('.sg', lim), lv = $('.lv', lim);
      hooks.push((t) => { const n = [0, 1, 2].filter((i) => t > a + 1.75 + i * 0.7).length; sg.forEach((s2, i) => { s2.style.background = i < n ? '#f4c95d' : 'rgba(255,255,255,.12)'; s2.style.boxShadow = i < n ? '0 0 14px rgba(244,201,93,.7)' : 'none'; }); lv.textContent = n + '/5';
        orb.firstChild; orb.style.filter = `brightness(${(1 + 0.25 * Math.sin(t * 9)).toFixed(3)})`; });
    })();

    /* ── F6 · hiring stages + talking to the employer ── */
    (function () {
      const g = groups[5], a = F[5];
      const st = add(g, `<div class="panel c" style="width:900px;height:230px;padding:30px 30px"><div class="row" style="justify-content:space-between">${['تقديم', 'فرز', 'مقابلة', 'عرض وظيفي'].map((s2) => `<div class="col" style="align-items:center;gap:14px;width:200px"><div class="nd" style="width:70px;height:70px;border-radius:50%;background:#16383d;border:3px solid rgba(125,243,232,.5);display:grid;place-items:center;color:#04282c"><div style="width:40px;height:40px;opacity:0" class="ci">${ic.check}</div></div><div class="ttl" style="font-size:30px">${s2}</div></div>`).join('')}</div>
        <div class="bar-bg" style="position:absolute;left:130px;right:130px;top:60px;height:8px;z-index:-1"><i></i></div></div>`);
      gsap.set(st, { x: 30, y: 0, z: 30 });
      const pv = { v: 0 }; tl.to(pv, { v: 0.667, duration: 1.3, ease: 'power1.inOut' }, a + 0.4);
      [0, 1, 2].forEach((i) => cue(a + 0.45 + i * 0.62, i === 2 ? 'ding' : 'pop', 0.7));
      const chat = add(g, `<div class="panel c p3d" style="width:900px;height:600px;padding:26px 30px"><div class="row"><div class="avatar"></div><div class="col"><div class="ttl" style="font-size:34px">المنشأة</div><div class="sub">مسؤول التوظيف</div></div></div></div>`);
      gsap.set(chat, { x: 30, y: 260, z: 10 });
      const dots = add(chat, `<div class="bubble them" style="right:30px;top:140px"><span class="dots"><i></i><i></i><i></i></span></div>`);
      enter(dots, { scale: 0, opacity: 0, transformOrigin: '100% 100%' }, { scale: 1, opacity: 1 }, a + 1.25, 0.3, 'back.out(2)'); tl.to(dots, { opacity: 0, duration: 0.1 }, a + 1.85);
      const b1 = add(chat, `<div class="bubble them" style="right:30px;top:140px;font-size:34px">يسعدنا دعوتك لمقابلة يوم الأحد</div>`);
      enter(b1, { scale: 0.5, opacity: 0, transformOrigin: '100% 100%', z: 40 }, { scale: 1, opacity: 1 }, a + 1.9, 0.4, 'back.out(1.8)'); cue(a + 1.9, 'ding', 0.9);
      const b2 = add(chat, `<div class="bubble me" style="left:30px;top:300px;font-size:34px">تمام، بالموعد إن شاء الله</div>`);
      enter(b2, { scale: 0.5, opacity: 0, transformOrigin: '0 100%', z: 40 }, { scale: 1, opacity: 1 }, a + 2.65, 0.4, 'back.out(1.8)'); cue(a + 2.65, 'pop', 0.8);
      const inv = add(chat, `<div class="kpi row" style="position:absolute;left:30px;right:30px;bottom:30px;border-color:rgba(244,201,93,.5)"><div style="width:50px;height:50px;color:#f4c95d">${ic.cal}</div><div class="ttl" style="font-size:32px">موعد المقابلة: الأحد 10:00 ص</div></div>`);
      enter(inv, { y: 40, opacity: 0 }, { y: 0, opacity: 1 }, a + 2.9, 0.4);
      const nds = $$('.nd', st), cis = $$('.ci', st), fill = $('.bar-bg i', st), dd = $$('.dots i', dots);
      hooks.push((t) => { fill.style.transform = `scaleX(${pv.v.toFixed(4)})`;
        nds.forEach((n, i) => { const on = pv.v >= i / 3 - 0.01 && t > a + 0.4, cur = i === 2 && on; n.style.background = on ? (cur ? '#f4c95d' : '#2ee6d6') : '#16383d'; n.style.boxShadow = on ? `0 0 26px ${cur ? 'rgba(244,201,93,.9)' : 'rgba(46,230,214,.8)'}` : 'none'; n.style.transform = `scale(${cur ? (1.12 + 0.06 * Math.sin(t * 7)).toFixed(3) : 1})`; cis[i].style.opacity = on && !cur ? 1 : 0; });
        dd.forEach((d, i) => { d.style.transform = `translateY(${(-Math.max(0, Math.sin(t * 9 - i * 0.9)) * 9).toFixed(1)}px)`; }); });
    })();

    /* ── F7 · the AI assistant ── */
    (function () {
      const g = groups[6], a = F[6];
      const orb = add(g, `<div class="orb c" style="width:150px;height:150px"></div>`); gsap.set(orb, { x: 770, y: 10, z: 80 });
      const nm = add(g, `<div class="c col" style="width:600px"><div class="ttl" style="font-size:42px">المساعد الذكي</div><div class="sub" style="font-size:30px">يوجهك خطوة بخطوة</div></div>`); gsap.set(nm, { x: 0, y: 30 });
      nm.style.left = 'auto'; nm.style.right = '230px';
      const b1 = add(g, `<div class="bubble me c" style="font-size:38px">كيف أرفع فرصي؟</div>`);
      enter(b1, { x: 30, y: 200, z: 40, scale: 0.5, opacity: 0, transformOrigin: '0 100%' }, { scale: 1, opacity: 1 }, a + 0.45, 0.4, 'back.out(1.8)'); cue(a + 0.45, 'pop', 0.8);
      const ans = add(g, `<div class="panel c p3d" style="width:800px;height:480px;padding:34px 36px;border-top-right-radius:10px"><div class="thinking row" style="gap:16px"><span class="dots"><i></i><i></i><i></i></span><span class="sub" style="font-size:30px">يحلل ملفك..</span></div></div>`);
      enter(ans, { x: 130, y: 380, z: 20, scale: 0.6, opacity: 0, transformOrigin: '100% 0' }, { y: 340, scale: 1, opacity: 1 }, a + 0.8, 0.45, 'back.out(1.5)');
      tl.to($('.thinking', ans), { opacity: 0, duration: 0.15 }, a + 1.3);
      [['أضف مشاريعك الأخيرة لسيرتك', 'doc'], ['قدم على 4 وظائف تناسب مهاراتك', 'brief'], ['جهز نفسك لأسئلة المقابلة', 'chat']].forEach(([txt, icn], i) => {
        const e = add(ans, `<div class="kpi row" style="position:absolute;left:30px;right:30px;top:${34 + i * 138}px;height:116px"><div class="ico" style="width:64px;height:64px;color:#9af7ee;border-radius:18px">${ic[icn]}</div><div class="ttl" style="font-size:33px">${txt}</div></div>`);
        enter(e, { x: -70, opacity: 0, z: 40 }, { x: 0, opacity: 1 }, a + 1.4 + i * 0.4, 0.45, 'power3.out'); cue(a + 1.4 + i * 0.4, 'pop', 0.6);
      });
      cue(a + 2.75, 'sparkle', 0.9);
      const dd = $$('.dots i', ans);
      hooks.push((t) => { orb.style.filter = `brightness(${(1 + 0.22 * Math.sin(t * 8)).toFixed(3)})`; dd.forEach((d, i) => { d.style.transform = `translateY(${(-Math.max(0, Math.sin(t * 9 - i * 0.9)) * 9).toFixed(1)}px)`; }); });
    })();

    /* character: stays with us through the whole tour */
    const ch = Char.bust({ variant: 'seeker', seed: 0.4 }); w.appendChild(ch.el);
    gsap.set(ch.el, { x: 285, y: 1300, z: 120, scale: 0.85, transformOrigin: '0 0' });
    const S = ch.s; Object.assign(S, { lookY: -0.9, brow: 0.5, glow: 0.55, smile: 1, eye: 1.05 });
    tl.to(S, { smile: 0.4, brow: 0.2, duration: 0.6 }, 32.2);
    F.slice(1, 7).forEach((t, i) => { tl.to(S, { bob: 9, duration: 0.16, ease: 'power2.in' }, t - 0.1).to(S, { bob: 0, duration: 0.4, ease: 'back.out(2)' }, t + 0.06);
      tl.to(S, { lookX: i % 2 ? 0.6 : -0.6, turn: i % 2 ? 0.3 : -0.3, duration: 0.7, ease: 'sine.inOut' }, t + 0.3).to(S, { lookX: 0, turn: 0, duration: 0.7, ease: 'sine.inOut' }, t + 1.8); });
    tl.to(S, { brow: 0.9, eye: 1.25, duration: 0.3 }, 34.9).to(S, { brow: 0.3, eye: 1.05, smile: 0.6, duration: 0.6 }, 35.5)
      .to(S, { smile: 0.85, duration: 0.5 }, 39.4).to(S, { brow: 0.8, smile: 1, duration: 0.4 }, 52.9).to(S, { brow: 0.4, duration: 0.6 }, 54.0).to(S, { smile: 1, brow: 0.6, lookY: -0.6, duration: 0.5 }, 56.6);
    tl.to(ch.el, { y: 2000, duration: 0.45, ease: 'power3.in' }, 57.55);

    gsap.set(sc.cam, { transformOrigin: '540px 900px' });
    enter(sc.cam, { rotationY: -5, rotationX: 2 }, { rotationY: 5, rotationX: -1 }, 32, 26, 'sine.inOut');
    cue(57.5, 'whoosh', 1); streaks(57.45, 58.3, { n: 30, seed: 12 });

    onFrame((t) => {
      if (t < 32 || t >= 58) return;
      ch.update(t);
      stepBars.forEach((b, i) => { b.style.transform = `scaleX(${prog(t, F[i], F[i + 1]).toFixed(4)})`; });
      for (const h of hooks) h(t);
    });
  })();


  /* ══════════ SCENE 5 · THE PATH (58 – 72) ══════════ */
  (function S5() {
    const sc = scene('s5', 58, 72.1), w = sc.world;
    const cam = { vy: 560, wd: 420, glow: 0.2, pulse: -1 };
    enter(cam, { vy: 470, wd: 520 }, { vy: 800, wd: 300 }, 58.2, 6.5, 'power2.inOut');
    tl.to(cam, { glow: 1, duration: 3, ease: 'sine.inOut' }, 61).to(cam, { pulse: 9, duration: 5.6, ease: 'none' }, 59.0);
    tl.to(dust, { gold: 1, rise: 900, duration: 12, ease: 'sine.inOut' }, 58);
    const P = (xw, d, h = 0) => { const k = 1 / (1 + d); return { x: 540 + xw * k, y: cam.vy + (1920 - cam.vy) * k - h * k, k }; };
    const OPP = [['محلل بيانات', 0.92], ['محلل أعمال', 0.88], ['أخصائي بيانات', 0.85], ['مدير مشاريع', 0.77], ['محلل مالي', 0.81], ['مطور تقارير', 0.74], ['باحث سوق', 0.7], ['منسق عمليات', 0.66]];
    const ops = OPP.map(([title, pct], i) => {
      const e = add(w, `<div class="panel c row" style="width:420px;height:150px;padding:0 24px;border-radius:26px;gap:16px">${UI.ring(i % 3 === 0 ? '#f4c95d' : '#2ee6d6', 92)}<div class="col"><div class="ttl" style="font-size:32px;white-space:nowrap">${title}</div><div class="sub" style="font-size:23px">فرصة تناسبك</div></div></div>`);
      return { e, ring: $('.ring', e), pct, d: 0.4 + i * 0.42, side: i % 2 ? 1 : -1 };
    });
    ops.forEach((o) => cue(59.0 + o.d / 1.6, 'pop', 0.55));
    const fig = Char.backFigure('seeker'); w.appendChild(fig.el);
    enter(fig.el, { x: 330 - 150, y: 2000, scale: 1.7, transformOrigin: '0 0', zIndex: 3000 }, { y: 960 }, 58.05, 0.9, 'power3.out');
    tl.to(fig.el, { x: 330 + 62, y: 1290, scale: 0.7, duration: 6.2, ease: 'power2.inOut' }, 58.9);
    particles({ n: 700, seed: 99, t0: 58.0, t1: 60.6, spread: 0.4, swirl: 380, size: 3, gold: 0.5, fadeIn: 0.1, fadeOut: 0.6, layer: 'back',
      from: (i, q) => ({ x: q() * 1080, y: q() * 1500 }), to: (i, q) => { const d = q() * 5, sd = q() < 0.5 ? -1 : 1, k = 1 / (1 + d); return { x: 540 + sd * 300 * k, y: 800 + 1120 * k }; } });

    const t1 = line(w, 'h1', 'رحلتك الوظيفية..', 200, 'font-size:88px;text-shadow:0 6px 40px rgba(0,0,0,.7)');
    const t2 = line(w, 'h1', 'تستحق تكون أذكى.', 330, 'font-size:100px;white-space:nowrap');
    reveal(t1, 61.0, { stagger: 0.62 });
    const w2 = E.words(t2); w2.forEach((x) => x.classList.add('gold'));
    [62.9, 63.55, 64.0].forEach((t, i) => { const wr = w2[i]; enter(wr, { y: 60, opacity: 0, scale: i === 2 ? 2.2 : 0.9 }, { y: 0, opacity: 1, scale: 1 }, t, i === 2 ? 0.45 : 0.5, i === 2 ? 'power4.out' : 'power3.out'); });
    flash(64.0, { color: '255,225,150', y: 520, a: 0.85, dur: 0.8 }); cue(64.0, 'impact', 1); cue(64.05, 'sparkle', 1); cue(61.0, 'swish', 0.6);
    tl.fromTo(sc.shake, { v: 28 }, { v: 0, duration: 0.6, ease: 'power2.out', immediateRender: false }, 64.0);
    out([t1, t2], 66.0, 0.45, { y: -50, scale: 1.05 });
    const soon = add(w, `<div class="c" style="left:0;width:1080px;top:230px;text-align:center"><div class="gold" style="font:800 190px/1.3 'Alexandria'">قريبا..</div></div>`);
    enter(soon, { scale: 2.6, opacity: 0 }, { scale: 1, opacity: 1 }, 66.85, 0.4, 'power4.out');
    tl.to(soon, { scale: 1.06, duration: 4.5, ease: 'sine.out' }, 67.25);
    flash(67.0, { color: '255,225,150', y: 450, a: 0.9, dur: 0.9 }); cue(66.5, 'riser', 0.8, { dur: 0.5 }); cue(67.0, 'impact', 1.1); cue(67.05, 'sparkle', 1);
    tl.fromTo(sc.shake, { v: 34 }, { v: 0, duration: 0.7, ease: 'power2.out', immediateRender: false }, 67.0);
    const t3 = line(w, 'h2 glowtxt', 'تجربة مختلفة تماما.', 520, 'font-size:76px');
    reveal(t3, 67.9, { stagger: 0.22 }); cue(67.9, 'swish', 0.6);
    tl.to('#fade', { opacity: 1, duration: 1.2, ease: 'power1.in' }, 70.5);
    cue(58.0, 'hit', 0.8);

    onFrame((t) => {
      if (t < 58) return;
      const ctx = E.back, vy = cam.vy;
      /* horizon glow */
      const hg = ctx.createRadialGradient(540, vy, 0, 540, vy, 900);
      hg.addColorStop(0, `rgba(255,226,150,${0.55 * cam.glow})`); hg.addColorStop(0.25, `rgba(244,201,93,${0.22 * cam.glow})`); hg.addColorStop(0.6, `rgba(46,230,214,${0.08})`); hg.addColorStop(1, 'rgba(46,230,214,0)');
      ctx.fillStyle = hg; ctx.fillRect(0, 0, 1080, 1920);
      const A = prog(t, 58.1, 59.2);
      /* the path */
      const a0 = P(-cam.wd, 0), b0 = P(cam.wd, 0), v = { x: 540, y: vy };
      const pg = ctx.createLinearGradient(0, 1920, 0, vy);
      pg.addColorStop(0, `rgba(46,230,214,${0.05 * A})`); pg.addColorStop(0.7, `rgba(244,201,93,${0.2 * A})`); pg.addColorStop(1, `rgba(255,236,180,${0.5 * A})`);
      ctx.fillStyle = pg; ctx.beginPath(); ctx.moveTo(a0.x, a0.y); ctx.lineTo(b0.x, b0.y); ctx.lineTo(v.x, v.y); ctx.closePath(); ctx.fill();
      ctx.lineCap = 'round';
      for (const sd of [-1, 1]) {
        const g = ctx.createLinearGradient(0, 1920, 0, vy); g.addColorStop(0, `rgba(125,243,232,${0.9 * A})`); g.addColorStop(1, `rgba(255,231,168,${A})`);
        ctx.strokeStyle = g; ctx.lineWidth = 5; ctx.beginPath(); ctx.moveTo(540 + sd * cam.wd, 1920); ctx.lineTo(v.x, v.y); ctx.stroke();
        ctx.strokeStyle = `rgba(125,243,232,${0.14 * A})`; ctx.lineWidth = 22; ctx.beginPath(); ctx.moveTo(540 + sd * cam.wd, 1920); ctx.lineTo(v.x, v.y); ctx.stroke();
      }
      for (let i = 0; i < 26; i++) {           // centre dashes streaming towards us = moving forward
        const d = ((i * 0.45 - t * 0.55) % 11.7 + 11.7) % 11.7, d2 = d + 0.16;
        const p1 = P(0, d), p2 = P(0, d2);
        ctx.strokeStyle = `rgba(255,236,180,${0.8 * A * clamp(1.2 - d / 10)})`; ctx.lineWidth = Math.max(1, 12 * p1.k);
        ctx.beginPath(); ctx.moveTo(p1.x, p1.y); ctx.lineTo(p2.x, p2.y); ctx.stroke();
      }
      if (cam.pulse > -0.5 && cam.pulse < 8.5) {  // light travelling down the path
        const p1 = P(-cam.wd, cam.pulse), p2 = P(cam.wd, cam.pulse);
        ctx.strokeStyle = 'rgba(255,255,255,.95)'; ctx.lineWidth = Math.max(2, 16 * p1.k); ctx.beginPath(); ctx.moveTo(p1.x, p1.y); ctx.lineTo(p2.x, p2.y); ctx.stroke();
        ctx.strokeStyle = 'rgba(244,201,93,.3)'; ctx.lineWidth = Math.max(6, 70 * p1.k); ctx.beginPath(); ctx.moveTo(p1.x, p1.y); ctx.lineTo(p2.x, p2.y); ctx.stroke();
      }
      /* opportunities lighting up along the way */
      ops.forEach((o, i) => {
        const on = prog(t, 59.0 + o.d / 1.6, 59.0 + o.d / 1.6 + 0.5, 'back.out(1.8)');
        const q = P(o.side * (cam.wd + 200), o.d, 150 + Math.sin(t * 1.4 + i) * 14), k = q.k * 1.3 * on;
        o.e.style.opacity = clamp(on * 1.5) * clamp(1.25 - o.d / 5);
        o.e.style.zIndex = 2000 - i;
        o.e.style.transformOrigin = '0 0';
        o.e.style.transform = `translate(${(q.x - 210 * k).toFixed(1)}px,${(q.y - 150 * k).toFixed(1)}px) scale(${k.toFixed(4)})`;
        UI.setRing(o.ring, o.pct * on);
      });
    });
  })();

  window.VO = [
    { line: 'a1', w: [0, 4], at: 0.45 }, { line: 'a1', w: [5, 5], at: 2.5 }, { line: 'a1', w: [6, 6], at: 3.25 }, { line: 'a1', w: [7, 7], at: 4.0 },
    { line: 'a2', w: [0, 0], at: 5.3 }, { line: 'a2', w: [1, 5], at: 6.0 },
    { line: 'b1', w: [0, 3], at: 10.6 }, { line: 'b1', w: [4, 5], at: 13.4 }, { line: 'b1', w: [6, 10], at: 15.6 },
    { line: 'c1', w: [0, 5], at: 20.8 }, { line: 'c1', w: [6, 7], at: 25.0 }, { line: 'c1', w: [8, 14], at: 27.2 },
    { line: 'd1', w: [0, 4], at: 32.3 }, { line: 'd1', w: [5, 7], at: 34.2 }, { line: 'd1', w: [8, 10], at: 36.5 }, { line: 'd1', w: [11, 12], at: 44.6 }, { line: 'd1', w: [13, 19], at: 47.3 },
    { line: 'e1', w: [0, 1], at: 61.0 }, { line: 'e1', w: [2, 4], at: 62.9 },
  ];
  window.MUSIC = { sections: [{ t: 0, kind: 'tension' }, { t: 10, kind: 'pulse' }, { t: 20, kind: 'reveal' }, { t: 32, kind: 'drive' }, { t: 58, kind: 'finale' }, { t: 70.5, kind: 'end' }], silences: [[4.7, 5.6]] };
  E.start({ duration: 72, audio: '../out/seeker.wav', captions: [
    { a: 0.45, b: 2.4, text: 'كم مرة قدمت على وظيفة؟' }, { a: 2.5, b: 3.2, text: 'عشر؟' }, { a: 3.25, b: 3.95, text: 'خمسين؟' }, { a: 4.0, b: 4.9, text: 'مية؟' },
    { a: 5.3, b: 5.95, text: 'طيب..' }, { a: 6.0, b: 9.0, text: 'تدري أصلا سيرتك مناسبة للوظيفة؟' },
    { a: 10.6, b: 13.0, text: 'تتنقل بين مواقع الشركات..' }, { a: 13.4, b: 15.1, text: 'تقدم وتنتظر..' }, { a: 15.6, b: 18.3, text: 'ولا تدري وين فرصتك الحقيقية!' },
    { a: 20.8, b: 24.0, text: 'تخيل مكان واحد يجمع لك الوظائف..' }, { a: 25.0, b: 26.7, text: 'ويحلل سيرتك..' }, { a: 27.2, b: 30.5, text: 'ويوضح لك مدى توافقك مع كل فرصة!' },
    { a: 32.3, b: 34.1, text: 'مو بس تبحث عن وظيفة..' }, { a: 34.2, b: 36.0, text: 'تعرف وين تناسبك..' }, { a: 36.5, b: 38.6, text: 'وكيف تطور سيرتك..' }, { a: 44.6, b: 46.5, text: 'وتتابع طلباتك..' },
    { a: 47.3, b: 51.1, text: 'وحتى الذكاء الاصطناعي يساعدك في رحلة التقديم!' },
    { a: 61.0, b: 62.8, text: 'رحلتك الوظيفية..' }, { a: 62.9, b: 65.3, text: 'تستحق تكون أذكى.' },
  ] });

})();
