/* Deterministic motion-graphics engine.
 * Everything on screen is a pure function of time: a paused GSAP master timeline
 * plus per-frame hooks. `seek(t)` renders the exact frame for time t, so frames
 * can be captured one by one (and in parallel) with no real-time dependency. */
(function () {
  const W = 1080, H = 1920;
  const tl = gsap.timeline({ paused: true, defaults: { ease: 'power3.out', overwrite: false } });
  const hooks = [];
  const scenes = [];

  const clamp = (v, a = 0, b = 1) => Math.min(b, Math.max(a, v));
  const lerp = (a, b, p) => a + (b - a) * p;
  const eases = {};
  const ez = (name) => eases[name] || (eases[name] = gsap.parseEase(name));
  /* eased progress of t through [a,b] */
  const prog = (t, a, b, ease = 'none') => ez(ease)(clamp((t - a) / (b - a)));
  /* 0→1→0 window: rises a..a+i, holds, falls b-o..b */
  const win = (t, a, b, i = 0.4, o = 0.4) => Math.min(prog(t, a, a + i, 'power2.out'), 1 - prog(t, b - o, b, 'power2.in'));

  function rng(seed) {
    let s = seed >>> 0;
    return function () {
      s |= 0; s = (s + 0x6d2b79f5) | 0;
      let x = Math.imul(s ^ (s >>> 15), 1 | s);
      x = (x + Math.imul(x ^ (x >>> 7), 61 | x)) ^ x;
      return ((x ^ (x >>> 14)) >>> 0) / 4294967296;
    };
  }

  const $ = (sel, root = document) => root.querySelector(sel);
  const $$ = (sel, root = document) => Array.from(root.querySelectorAll(sel));
  function el(html) { const d = document.createElement('div'); d.innerHTML = html.trim(); return d.firstElementChild; }
  function add(parent, html) { const e = el(html); parent.appendChild(e); return e; }

  /* A scene is only in the render tree between a and b. */
  function scene(id, a, b) {
    const root = add($('#scenes'), `<div class="scene" id="${id}"><div class="drift"><div class="world cam"><div class="world in"></div></div></div></div>`);
    const s = { id, a, b, root, drift: $('.drift', root), cam: $('.cam', root), world: $('.in', root), shake: { v: 0 } };
    scenes.push(s);
    return s;
  }

  /* First tween of an element: state is applied immediately at build time. */
  function enter(target, from, to, at, dur = 0.7, ease = 'power3.out') {
    gsap.set(target, from);
    return tl.fromTo(target, from, { ...to, duration: dur, ease, immediateRender: false }, at);
  }
  function to(target, vars, at, dur = 0.7, ease = 'power3.inOut') {
    return tl.to(target, { ...vars, duration: dur, ease }, at);
  }
  /* pop-in with overshoot */
  function pop(target, at, dur = 0.6, extra = {}) {
    return enter(target, { scale: 0.4, opacity: 0, ...(extra.from || {}) }, { scale: 1, opacity: 1, ...(extra.to || {}) }, at, dur, 'back.out(1.9)');
  }
  function out(target, at, dur = 0.45, vars = {}) {
    return tl.to(target, { opacity: 0, duration: dur, ease: 'power2.in', ...vars }, at);
  }

  /* Split a text element into word spans (never letters: Arabic shaping must stay intact). */
  function words(node) {
    const txt = node.textContent;
    node.textContent = '';
    const spans = [];
    txt.trim().split(/\s+/).forEach((part, i) => {
      const s = document.createElement('span'); s.className = 'w'; s.textContent = part;
      if (i) s.style.marginInlineStart = '0.27em';
      node.appendChild(s); spans.push(s);
    });
    return spans;
  }
  /* Kinetic word reveal */
  function reveal(node, at, opt = {}) {
    const ws = words(node);
    const st = opt.stagger ?? 0.09, dur = opt.dur ?? 0.65;
    ws.forEach((w, i) => {
      enter(w, { y: opt.y ?? 46, opacity: 0, scale: opt.scale ?? 0.92, filter: 'blur(14px)' }, { y: 0, opacity: 1, scale: 1, filter: 'blur(0px)' }, at + i * st, dur, opt.ease || 'power3.out');
    });
    return ws;
  }

  function onFrame(fn) { hooks.push(fn); }

  /* ───────── Canvas FX ───────── */
  let back, front, DPR = 1;
  function initCanvas() {
    DPR = window.devicePixelRatio || 1;
    [back, front] = ['fxBack', 'fxFront'].map((id) => {
      const c = document.getElementById(id);
      c.width = W * DPR; c.height = H * DPR;
      const ctx = c.getContext('2d'); ctx.scale(DPR, DPR); return ctx;
    });
  }

  /* Soft bokeh dust that lives behind every scene. `dust.gold` (0..1) warms it up, `dust.speed` drives drift. */
  const dust = { gold: 0, alpha: 1, n: 64, items: null, rise: 0 };
  function drawDust(t) {
    if (!dust.items) {
      const r = rng(7);
      dust.items = Array.from({ length: dust.n }, () => ({ x: r() * W, y: r() * H, z: 0.25 + r() * 0.75, ph: r() * 6.28, sp: 0.4 + r(), g: r() }));
    }
    const ctx = back;
    ctx.globalCompositeOperation = 'lighter';
    for (const p of dust.items) {
      const y = (((p.y - (t * 26 + dust.rise) * p.z * p.sp) % (H + 200)) + H + 200) % (H + 200) - 100;
      const x = p.x + Math.sin(t * 0.35 * p.sp + p.ph) * 46 * p.z;
      const rad = 5 + (1 - p.z) * 46;
      const tw = 0.55 + 0.45 * Math.sin(t * 1.3 * p.sp + p.ph * 3);
      const a = dust.alpha * tw * (0.05 + p.z * 0.12);
      const gold = p.g < 0.18 + dust.gold * 0.55;
      const col = gold ? '244,201,93' : '70,235,220';
      const g = ctx.createRadialGradient(x, y, 0, x, y, rad);
      g.addColorStop(0, `rgba(${col},${a})`); g.addColorStop(0.55, `rgba(${col},${a * 0.45})`); g.addColorStop(1, `rgba(${col},0)`);
      ctx.fillStyle = g; ctx.beginPath(); ctx.arc(x, y, rad, 0, 6.2832); ctx.fill();
    }
    ctx.globalCompositeOperation = 'source-over';
  }

  /* Particle morph system: every particle travels from(i) → to(i) between t0 and t1 with a swirl,
   * staggered by `spread`. Positions are pure functions of t. */
  const systems = [];
  function particles(o) {
    const r = rng(o.seed || 1);
    const ps = [];
    for (let i = 0; i < o.n; i++) {
      const a = o.from(i, r), b = o.to(i, r);
      ps.push({ ax: a.x, ay: a.y, bx: b.x, by: b.y, d: r() * (o.spread ?? 0.35), sw: (r() - 0.5) * 2 * (o.swirl ?? 260), sz: (o.size ?? 3) * (0.5 + r()), ph: r() * 6.28,
        gold: r() < (o.gold ?? 0.2) });
    }
    const sys = { ...o, ps, layer: o.layer || 'front' };
    systems.push(sys);
    return sys;
  }
  function drawSystems(t) {
    for (const s of systems) {
      const fin = s.fadeIn ?? 0.25, fout = s.fadeOut ?? 0.35;
      if (t < s.t0 - (s.pre ?? 0) || t > s.t1 + (s.hold ?? 0) + fout) continue;
      const ctx = s.layer === 'back' ? back : front;
      ctx.globalCompositeOperation = 'lighter';
      const span = s.t1 - s.t0;
      const galpha = Math.min(prog(t, s.t0 - (s.pre ?? 0), s.t0 - (s.pre ?? 0) + fin), 1 - prog(t, s.t1 + (s.hold ?? 0), s.t1 + (s.hold ?? 0) + fout)) * (s.alpha ?? 1);
      for (const p of s.ps) {
        const raw = clamp((t - s.t0 - p.d * span) / (span * (1 - (s.spread ?? 0.35))));
        const e = ez(s.ease || 'power2.inOut')(raw);
        const arc = Math.sin(raw * Math.PI);
        const dx = p.bx - p.ax, dy = p.by - p.ay, len = Math.hypot(dx, dy) || 1;
        let x = lerp(p.ax, p.bx, e) + (-dy / len) * p.sw * arc + Math.sin(t * 2 + p.ph) * 5;
        let y = lerp(p.ay, p.by, e) + (dx / len) * p.sw * arc + Math.cos(t * 1.7 + p.ph) * 5;
        const tw = 0.6 + 0.4 * Math.sin(t * 9 + p.ph * 5);
        const a = galpha * tw;
        const rad = p.sz * (1 + arc * 0.8);
        ctx.fillStyle = p.gold ? `rgba(255,214,120,${a})` : `rgba(110,245,232,${a})`;
        ctx.beginPath(); ctx.arc(x, y, rad, 0, 6.2832); ctx.fill();
        ctx.fillStyle = p.gold ? `rgba(255,214,120,${a * 0.18})` : `rgba(110,245,232,${a * 0.18})`;
        ctx.beginPath(); ctx.arc(x, y, rad * 3.4, 0, 6.2832); ctx.fill();
      }
      ctx.globalCompositeOperation = 'source-over';
    }
  }

  /* Full-frame flashes & speed streaks (for whoosh transitions). */
  const flashes = [];   // {t, dur, color, x, y, r}
  function flash(t, o = {}) { flashes.push({ t, dur: o.dur ?? 0.55, color: o.color || '200,255,250', x: o.x ?? W / 2, y: o.y ?? H / 2, r: o.r ?? 1500, a: o.a ?? 0.9 }); }
  const streakSets = []; // {t0,t1,n,seed,angle}
  function streaks(t0, t1, o = {}) { streakSets.push({ t0, t1, n: o.n ?? 26, seed: o.seed ?? 3, vertical: !!o.vertical, color: o.color || '125,243,232', r: null }); }
  function drawOverlays(t) {
    const ctx = front;
    for (const f of flashes) {
      if (t < f.t || t > f.t + f.dur) continue;
      const p = (t - f.t) / f.dur;
      const a = f.a * Math.pow(1 - p, 2.2);
      const g = ctx.createRadialGradient(f.x, f.y, 0, f.x, f.y, f.r * (0.35 + p * 0.65));
      g.addColorStop(0, `rgba(${f.color},${a})`); g.addColorStop(0.5, `rgba(${f.color},${a * 0.35})`); g.addColorStop(1, `rgba(${f.color},0)`);
      ctx.globalCompositeOperation = 'lighter'; ctx.fillStyle = g; ctx.fillRect(0, 0, W, H); ctx.globalCompositeOperation = 'source-over';
    }
    for (const s of streakSets) {
      if (t < s.t0 || t > s.t1) continue;
      if (!s.r) { const r = rng(s.seed); s.r = Array.from({ length: s.n }, () => ({ u: r(), v: r(), l: 200 + r() * 700, w: 1 + r() * 5, sp: 0.7 + r() * 1.2 })); }
      const p = (t - s.t0) / (s.t1 - s.t0);
      const a = Math.sin(p * Math.PI);
      ctx.globalCompositeOperation = 'lighter';
      for (const k of s.r) {
        const trav = (p * k.sp * 2.4 + k.u) % 1.4 - 0.2;
        let x0, y0, x1, y1;
        if (s.vertical) { x0 = x1 = k.v * W; y0 = H * (1 - trav) ; y1 = y0 + k.l; }
        else { y0 = y1 = k.v * H; x0 = W * (1 - trav); x1 = x0 + k.l; }
        const g = ctx.createLinearGradient(x0, y0, x1, y1);
        g.addColorStop(0, `rgba(${s.color},${0.75 * a})`); g.addColorStop(1, `rgba(${s.color},0)`);
        ctx.strokeStyle = g; ctx.lineWidth = k.w; ctx.lineCap = 'round';
        ctx.beginPath(); ctx.moveTo(x0, y0); ctx.lineTo(x1, y1); ctx.stroke();
      }
      ctx.globalCompositeOperation = 'source-over';
    }
  }

  /* Subtle hand-held drift so that even held shots stay alive. */
  function applyDrift(t) {
    for (const s of scenes) {
      if (s.root.style.display !== 'block') continue;
      const k = s.driftAmt ?? 1;
      const sh = s.shake.v;
      const r = sh ? rng(Math.floor(t * 60) + 11) : null;
      const sx = sh ? (r() - 0.5) * sh : 0, sy = sh ? (r() - 0.5) * sh : 0;
      s.drift.style.transform =
        `translate3d(${(Math.sin(t * 0.43) * 7 * k + sx).toFixed(2)}px,${(Math.cos(t * 0.37) * 9 * k + sy).toFixed(2)}px,0) rotateX(${(Math.sin(t * 0.31 + 1) * 0.7 * k).toFixed(3)}deg) rotateY(${(Math.sin(t * 0.27) * 1.1 * k).toFixed(3)}deg)`;
    }
  }

  let duration = 60;
  let captions = [];      // [{a,b,text}] – only shown when ?cc=1 (mute-friendly pass)
  let showCC = false;
  function seek(t) {
    for (const s of scenes) s.root.style.display = t >= s.a && t < s.b ? 'block' : 'none';
    tl.time(t, true);
    back.clearRect(0, 0, W, H); front.clearRect(0, 0, W, H);
    drawDust(t);
    for (const h of hooks) h(t);
    drawSystems(t);
    drawOverlays(t);
    applyDrift(t);
    if (showCC) {
      const cap = $('#caption'); const c = captions.find((c) => t >= c.a && t < c.b);
      if (c) { cap.style.display = 'block'; cap.firstElementChild.textContent = c.text; cap.style.opacity = Math.min(prog(t, c.a, c.a + 0.18), 1 - prog(t, c.b - 0.18, c.b)); }
      else cap.style.display = 'none';
    }
  }

  function start(opts) {
    duration = opts.duration;
    captions = opts.captions || [];
    const q = new URLSearchParams(location.search);
    showCC = q.get('cc') === '1';
    initCanvas();
    window.DURATION = duration;
    window.seek = seek;
    document.fonts.ready.then(() => {
      seek(parseFloat(q.get('t') || '0'));
      window.READY = true;
      if (q.get('play') === '1') {     // live preview with audio
        const stage = $('#stage');
        const k = Math.min(innerWidth / W, innerHeight / H); stage.style.transform = `scale(${k})`;
        const audio = new Audio(opts.audio || ''); let t0 = null;
        const loop = (now) => { if (t0 === null) t0 = now; const t = audio.src && !audio.paused ? audio.currentTime : (now - t0) / 1000; if (t < duration) { seek(t); requestAnimationFrame(loop); } };
        addEventListener('click', () => { audio.play().catch(() => {}); t0 = null; requestAnimationFrame(loop); }, { once: true });
      }
    });
  }

  window.SFX = [];
  const cue = (t, type, g = 1, extra = {}) => window.SFX.push({ t: +t.toFixed(3), type, g, ...extra });
  window.E = { cue, W, H, tl, $, $$, el, add, scene, enter, to, pop, out, words, reveal, onFrame, particles, flash, streaks, dust, prog, win, clamp, lerp, ez, rng, start, seek,
    get back() { return back; }, get front() { return front; } };
})();
