/* Film 2 – employers & hiring managers: «التوظيف ما لازم يكون بهذه الصعوبة!»   (72 s, 120 BPM grid: 1 beat = 0.5 s) */
(function () {
  const { tl, $, $$, add, scene, enter, to, pop, out, reveal, onFrame, prog, win, clamp, lerp, rng, flash, streaks, particles, dust, cue } = E;
  const ic = UI.ic;
  const line = (parent, cls, text, top, extra = '') => add(parent, `<div class="c ${cls}" style="left:40px;width:1000px;top:${top}px;${extra}">${text}</div>`);
  const icon = (name, size = 44, color = '#9af7ee') => `<span style="width:${size}px;height:${size}px;display:inline-block;color:${color};flex:none">${ic[name]}</span>`;
  const sk = (w, cls = '', extra = '') => `<div class="sk ${cls}" style="width:${w};${extra}"></div>`;
  const tag = (txt = 'مثال توضيحي') => `<span class="tag-ex">${txt}</span>`;
  const outC = (p) => 1 - Math.pow(1 - clamp(p), 3);
  const back = (p) => E.ez('back.out(1.7)')(clamp(p));

  /* analogue clock dial (motif of the film) */
  function dial(size, color = '#f4c95d') {
    let ticks = '';
    for (let i = 0; i < 60; i++) {
      const a = i * 6 * Math.PI / 180, big = i % 5 === 0, r0 = big ? 258 : 272, r1 = 290;
      ticks += `<path d="M${(330 + Math.sin(a) * r0).toFixed(1)} ${(330 - Math.cos(a) * r0).toFixed(1)}L${(330 + Math.sin(a) * r1).toFixed(1)} ${(330 - Math.cos(a) * r1).toFixed(1)}" stroke="${color}" stroke-width="${big ? 7 : 3}" stroke-linecap="round" opacity="${big ? 0.95 : 0.5}"/>`;
    }
    const e = E.el(`<div class="c" style="width:${size}px;height:${size}px"><svg viewBox="0 0 660 660" width="${size}" height="${size}" style="overflow:visible;display:block;filter:drop-shadow(0 0 26px ${color}88)">
      <circle cx="330" cy="330" r="312" fill="rgba(4,24,27,.55)" stroke="${color}" stroke-width="7"/>
      <circle cx="330" cy="330" r="300" fill="none" stroke="${color}" stroke-width="2" opacity=".4"/>${ticks}
      <path data-k="h" d="M330 346V176" stroke="#fff" stroke-width="16" stroke-linecap="round"/>
      <path data-k="m" d="M330 356V84" stroke="${color}" stroke-width="10" stroke-linecap="round"/>
      <circle cx="330" cy="330" r="17" fill="${color}"/></svg></div>`);
    const h = e.querySelector('[data-k="h"]'), m = e.querySelector('[data-k="m"]');
    return { el: e, set(turns) { m.setAttribute('transform', `rotate(${((turns * 360) % 360).toFixed(2)} 330 330)`); h.setAttribute('transform', `rotate(${((turns * 30 + 40) % 360).toFixed(2)} 330 330)`); } };
  }
  const sheetHTML = () => `<div class="sheet">
    <div class="pf"><div class="row" style="gap:14px"><div class="av"></div><div class="col" style="gap:10px;flex:1">${sk('72%', 't')}${sk('46%')}</div></div><div class="col" style="gap:13px;margin-top:22px">${sk('94%')}${sk('84%')}${sk('60%')}${sk('34%', 't', 'margin-top:8px')}${sk('90%')}${sk('74%')}${sk('52%')}</div></div>
    <div class="df"><div class="row" style="gap:14px"><div class="av"></div><div class="col" style="gap:10px;flex:1">${sk('72%')}${sk('46%')}</div></div><div class="col" style="gap:13px;margin-top:22px">${sk('94%')}${sk('84%')}${sk('60%')}${sk('34%', '', 'margin-top:8px')}${sk('90%')}${sk('74%')}${sk('52%')}</div></div>
    <div class="gf"><div class="row" style="gap:14px"><div class="av"></div><div class="col" style="gap:10px;flex:1">${sk('72%')}${sk('46%')}</div></div><div class="col" style="gap:13px;margin-top:22px">${sk('94%')}${sk('84%')}${sk('60%')}${sk('34%', '', 'margin-top:8px')}${sk('90%')}${sk('74%')}${sk('52%')}</div></div></div>`;

  /* ══════════ SCENE 1 · HOOK (0 – 10) ══════════ */
  (function S1() {
    const sc = scene('e1', 0, 10), w = sc.world;
    sc.root.insertBefore(E.el(`<div class="floor"></div>`), sc.drift);
    const clock = { v: 0 };                       // local time: real-time until 5.6, then slow motion
    tl.to(clock, { v: 5.6, duration: 5.6, ease: 'none' }, 0).to(clock, { v: 6.75, duration: 4.4, ease: 'power2.out' }, 5.6);

    const dim = add(w, `<div class="c" style="left:-3000px;top:-3000px;width:7000px;height:8000px;background:#020c0e"></div>`);
    gsap.set(dim, { z: -140, opacity: 0 });
    tl.to(dim, { opacity: 0.45, duration: 0.9, ease: 'power2.out' }, 5.7);

    /* the clock behind him */
    const dl = dial(700); w.appendChild(dl.el);
    gsap.set(dl.el, { x: 190, y: 250, z: -330 });

    /* vacant-job card with the live applicants counter */
    const job = add(w, `<div class="panel gold-edge c" style="width:900px;height:200px;padding:0 40px;display:flex;align-items:center;gap:24px">
      <div class="ico" style="width:96px;height:96px;color:#ffe7a8;background:linear-gradient(145deg,#8a6a22,#3f2f0c);border-color:rgba(244,201,93,.5)">${ic.brief}</div>
      <div class="col" style="gap:6px;flex:1"><div class="ttl" style="font-size:46px">وظيفة شاغرة</div><div class="sub" style="font-size:28px">مهندس برمجيات · الرياض</div></div>
      <div class="col" style="align-items:center;gap:0"><div class="num" style="font-size:96px;line-height:1.05;color:#fff;text-shadow:0 0 40px rgba(46,230,214,.6)"></div><div class="lbl" style="font-size:27px">متقدمون</div></div>
      <div class="sheen"><i></i></div></div>`);
    gsap.set(job, { x: 90, y: 70, z: -60 });
    const cntNum = $('.num', job);
    const keys = [[0.3, 0], [2.8, 64], [5.6, 347], [99, 347]];
    const countAt = (c) => { for (let i = 1; i < keys.length; i++) if (c <= keys[i][0]) { const [a, va] = keys[i - 1], [b, vb] = keys[i]; return Math.round(lerp(va, vb, Math.pow(clamp((c - a) / (b - a)), 1.5))); } return 347; };
    tl.fromTo($('.sheen i', job), { left: '-40%' }, { left: '120%', duration: 1.1, ease: 'power2.inOut', immediateRender: false }, 0.5);
    tl.to(job, { opacity: 0, y: 10, duration: 0.45, ease: 'power2.in' }, 6.25);

    /* desk + manager */
    const desk = add(w, `<div class="e-desk c" style="top:1540px"></div>`); gsap.set(desk, { z: 10 });
    const ch = Char.bust({ variant: 'manager', seed: 2.9 }); w.appendChild(ch.el);
    gsap.set(ch.el, { x: 165, y: 620, scale: 1.25, transformOrigin: '0 0' });
    const S = ch.s;
    Object.assign(S, { brow: -0.35, lookX: -0.7, lookY: 0.2, glow: 0.2, smile: -0.2, turn: -0.3 });
    tl.to(S, { eye: 1.32, brow: 0.95, open: 0.5, lookX: 0, lookY: 0, turn: 0, duration: 0.2, ease: 'power3.out' }, 0.3)
      .to(S, { eye: 1.05, brow: -0.6, open: 0.15, turn: 0.55, lookX: 0.7, lookY: -0.3, tilt: 3, duration: 0.9, ease: 'sine.inOut' }, 1.2)
      .to(S, { turn: -0.55, lookX: -0.7, tilt: -3, glow: 0.55, duration: 1.2, ease: 'sine.inOut' }, 2.4)
      .to(S, { turn: 0.45, lookX: 0.6, lookY: -0.5, tilt: 2, sweat: 1, brow: -0.9, duration: 1.2, ease: 'sine.inOut' }, 3.8)
      .to(S, { turn: 0, lookX: 0, lookY: 0, tilt: -3, open: 0, smile: -0.5, duration: 0.9, ease: 'power2.inOut' }, 5.5)
      .to(S, { lookX: 0.8, lookY: -0.35, turn: 0.4, tilt: 2, brow: 0.6, eye: 1.2, smile: -0.1, duration: 0.5, ease: 'power3.out' }, 8.35);

    /* CV sheets: two towers + a low pile, then a vortex of documents */
    const r = rng(77);
    const P = [];
    const mk = (bx, i, n, zs, step) => {
      const e = add(w, sheetHTML());
      const [pf, df, gf] = e.children;
      const yb = 250 + r() * 1230, inFace = yb > 700 && yb < 1250;
      P.push({ e, pf, df, gf, sx: bx + (r() - 0.5) * 22, sy: 1500 - i * step, sz: zs, srot: (r() - 0.5) * 7, L: 0.3 + (n - 1 - i) * 0.034 + r() * 0.05,
        inFace, th0: r() * 6.283, om: (0.5 + r() * 0.55) * (r() < 0.5 ? 1 : -1), R: (inFace ? 500 : 330) + r() * 260, yb, ph: r() * 6.28, i: P.length });
    };
    for (let i = 0; i < 23; i++) mk(30, i, 23, 60, 26);
    for (let i = 0; i < 23; i++) mk(800, i, 23, 60, 26);
    for (let i = 0; i < 9; i++) mk(415, i, 9, 120, 24);
    const G = P[30];                       // the one right candidate, unseen among hundreds
    G.yb = 600; G.R = 420;

    /* text */
    const q1 = line(w, 'h2 glowtxt', 'بس كيف تعرف..', 300);
    reveal(q1, 5.75, { stagger: 0.16 });
    const q2 = add(w, `<div class="c" style="left:0;width:1080px;top:392px;text-align:center"><div class="gold" style="font:800 128px/1.3 'Alexandria'">مين الأنسب؟</div></div>`);
    gsap.set(q2, { transformOrigin: '50% 50%' });
    enter(q2, { scale: 1.7, opacity: 0 }, { scale: 1, opacity: 1 }, 6.7, 0.45, 'back.out(1.6)');
    tl.to(q2, { scale: 1.12, duration: 0.12, ease: 'power2.out' }, 8.5).to(q2, { scale: 1, duration: 0.5, ease: 'power2.out' }, 8.62);
    cue(6.7, 'pop', 0.9);

    /* impact: the right one lights up */
    tl.fromTo(sc.shake, { v: 30 }, { v: 0, duration: 0.6, ease: 'power2.out', immediateRender: false }, 8.5);
    flash(8.5, { color: '255,225,150', x: 900, y: 830, r: 1100, a: 0.8 });
    cue(8.5, 'impact', 1); cue(8.3, 'sparkle', 0.8);

    /* camera */
    gsap.set(w, { transformOrigin: '540px 1000px', scale: 1.32 });
    tl.to(w, { scale: 1, duration: 1.1, ease: 'expo.out' }, 0.3);
    gsap.set(sc.cam, { transformOrigin: '540px 1000px' });
    tl.to(sc.cam, { scale: 1.07, duration: 3.6, ease: 'sine.inOut' }, 5.7);
    tl.to(sc.cam, { x: -2600, duration: 0.5, ease: 'power3.in' }, 9.5);
    tl.fromTo(sc.shake, { v: 26 }, { v: 0, duration: 0.5, ease: 'power2.out', immediateRender: false }, 0.3);
    flash(0.3, { x: 540, y: 1200, r: 1300, a: 0.5, dur: 0.45 });
    cue(0, 'hit', 0.7); cue(0.3, 'hit', 1); cue(0.32, 'whoosh', 0.9); cue(9.45, 'whoosh', 1);
    cue(5.2, 'freeze', 0.7);
    for (let t = 1; t < 5.6; t += t < 3 ? 0.5 : 0.25) cue(t, 'tick', 0.35 + t * 0.08);
    streaks(9.45, 10.4, { n: 34, seed: 9 });

    /* hundreds of far documents on the back canvas */
    const far = Array.from({ length: 230 }, () => ({ th: r() * 6.283, om: (0.25 + r() * 0.5) * (r() < 0.5 ? 1 : -1), R: 180 + r() * 900, y: 120 + r() * 1500, s: 0.5 + r(), d: r() }));

    onFrame((t) => {
      if (t >= 10) return;
      const c = clock.v;
      ch.update(t);
      dl.set(c * 0.35 + Math.pow(c, 2.5) * 0.16);
      cntNum.textContent = (c >= 5.6 ? '+' : '') + countAt(c);
      const slow = prog(t, 5.7, 6.6);
      /* far docs */
      const fa = prog(c, 2.5, 4.6) * (1 - slow * 0.55);
      if (fa > 0) {
        const ctx = E.back;
        for (const f of far) {
          if (f.d > prog(c, 2.5, 5.4) * 1.05) continue;
          const th = f.th + f.om * c, dep = Math.sin(th) * 0.5 + 0.5;
          const x = 540 + Math.cos(th) * f.R, y = f.y + Math.sin(c * 0.7 + f.th) * 24, sz = (12 + dep * 20) * f.s;
          ctx.strokeStyle = `rgba(110,240,228,${(0.16 + dep * 0.42) * fa})`; ctx.lineWidth = 1.6;
          ctx.fillStyle = `rgba(20,90,98,${(0.2 + dep * 0.3) * fa})`;
          ctx.beginPath(); ctx.roundRect(x - sz * 0.38, y - sz * 0.5, sz * 0.76, sz, 3); ctx.fill(); ctx.stroke();
          ctx.beginPath(); ctx.moveTo(x - sz * 0.22, y - sz * 0.2); ctx.lineTo(x + sz * 0.22, y - sz * 0.2); ctx.moveTo(x - sz * 0.22, y + sz * 0.05); ctx.lineTo(x + sz * 0.12, y + sz * 0.05); ctx.stroke();
        }
      }
      /* sheets */
      const gp = prog(t, 6.9, 8.3, 'power2.inOut');
      for (const k of P) {
        const u = (c - k.L) / 0.95, e = outC(u), kick = u > 0 && u < 1 ? Math.sin(u * Math.PI) : 0;
        const th = k.th0 + k.om * Math.max(0, c - k.L);
        let x = lerp(k.sx, 415 + Math.cos(th) * k.R, e);
        let y = lerp(k.sy - 165, k.yb - 165 + Math.sin(c * 0.8 + k.ph) * 46, e) - kick * 150;
        let z = lerp(k.sz, (k.inFace ? -Math.abs(Math.sin(th)) : Math.sin(th)) * k.R * 0.8 - 190 - slow * 380, e) + kick * (k.inFace ? 160 : 420);
        let rx = lerp(81, Math.sin(c * 1.2 + k.ph) * 24, e), ry = Math.sin(c * 0.95 + k.ph * 2) * 46 * e, rz = lerp(k.srot, Math.sin(c * 0.7 + k.ph) * 16, e), s = lerp(1, 0.74, e);
        const d = prog(c, 2.7 + k.i * 0.03, 3.4 + k.i * 0.03);
        let bright = 1 - slow * 0.3;
        if (k === G) { x = lerp(x, 790, gp); y = lerp(y, 650, gp); z = lerp(z, 70, gp); rx = lerp(rx, 0, gp); ry = lerp(ry, -14, gp); rz = lerp(rz, 5, gp); s = lerp(s, 1, gp); bright = 1; }
        const g = k === G ? prog(t, 8.42, 8.62) : 0;
        k.pf.style.opacity = (1 - d).toFixed(3);
        k.df.style.opacity = (d * (1 - g)).toFixed(3);
        k.gf.style.opacity = g.toFixed(3);
        const blur = k === G && gp > 0.5 ? 0 : z > 140 ? Math.min(9, (z - 140) / 28) : z < -420 ? Math.min(4, (-420 - z) / 80) : 0;
        k.e.style.filter = blur > 0.4 || bright < 0.99 ? `blur(${blur.toFixed(1)}px) brightness(${bright.toFixed(2)})` : 'none';
        k.e.style.transform = `translate3d(${x.toFixed(1)}px,${y.toFixed(1)}px,${z.toFixed(1)}px) rotateX(${rx.toFixed(1)}deg) rotateY(${ry.toFixed(1)}deg) rotateZ(${rz.toFixed(1)}deg) scale(${s.toFixed(3)})`;
      }
    });
  })();


  /* ══════════ SCENE 2 · THE PROBLEM (10 – 16.4, three whip-pan stations) ══════════ */
  (function S2() {
    const sc = scene('e2', 9.8, 16.85), w = sc.world;      // overlaps the whip-pan out of scene 1
    const ST = 1500;                                // distance between stations
    sc.driftAmt = 1.4;
    enter(sc.cam, { x: 2600 }, { x: 0 }, 9.8, 0.6, 'power3.out');
    tl.to(sc.cam, { x: -ST, duration: 0.5, ease: 'power4.inOut' }, 12.15)
      .to(sc.cam, { x: -2 * ST, duration: 0.5, ease: 'power4.inOut' }, 13.95)
      .to(sc.cam, { x: -2 * ST - 2600, duration: 0.5, ease: 'power3.in' }, 16.15);
    [12.15, 13.95, 16.15].forEach((t, i) => { cue(t, 'whoosh', 0.85); streaks(t - 0.05, t + 0.6, { n: 26, seed: 20 + i }); });
    for (let t = 10.5; t < 16.4; t += 0.5) cue(t, 'tick', 0.5);

    /* ── A · manual CV screening ── */
    const hA = line(w, 'h2 glowtxt', 'فرز يدوي.. سيرة سيرة', 110); reveal(hA, 10.3);
    const cntA = add(w, `<div class="c" style="left:90px;top:268px;width:900px"><div class="row" style="justify-content:space-between"><div class="lbl" style="font-size:32px">سير تمت مراجعتها</div>
      <div style="font:800 62px/1.2 'Alexandria';color:#fff"><span class="num" data-k="n"></span> <span style="font-size:36px;color:var(--mute)">من</span> <span class="num">347</span></div></div>
      <div class="bar-bg" style="margin-top:12px;height:14px"><i></i></div></div>`);
    const nA = $('[data-k="n"]', cntA), barA = $('.bar-bg i', cntA);
    const xsvg = `<svg viewBox="0 0 24 24" width="84" height="84" fill="none" stroke="#e0574f" stroke-width="3.6" stroke-linecap="round"><path d="M6 6l12 12M18 6L6 18"/></svg>`;
    const pages = [];
    for (let k = 5; k >= 0; k--) {
      const e = add(w, UI.cv(560, 740, `<div class="scan" style="top:0;opacity:0"></div><div class="stamp" style="left:60px;top:500px">${xsvg}</div>`));
      pages[k] = { e, scan: $('.scan', e), stamp: $('.stamp', e), f: 10.62 + k * 0.42 };
    }
    const chA = Char.bust({ variant: 'manager', seed: 2.9 }); w.appendChild(chA.el);
    gsap.set(chA.el, { x: 270, y: 1330, scale: 0.9, transformOrigin: '0 0', z: 60 });
    Object.assign(chA.s, { brow: -0.5, furrow: 0.5, smile: -0.35, lookY: -0.7, glow: 0.1, tilt: -2 });
    pages.slice(0, 5).forEach((p) => { cue(p.f, 'swish', 0.7); cue(p.f - 0.36, 'scan', 0.4, { dur: 0.3 }); });

    /* ── B · interviews: colliding calendar ── */
    const B = ST;
    const hB = line(w, 'h2 glowtxt', 'مقابلات.. ومواعيد تتعارض', 110, `left:${B + 40}px`); reveal(hB, 12.5);
    const days = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس'];
    const CW = 160, CG = 13, RH = 130, RG = 12;
    const cx = (c) => 852 - (c + 1) * CW - c * CG, cy = (r) => 64 + r * (RH + RG);
    let cells = '';
    for (let c = 0; c < 5; c++) {
      cells += `<div class="a" style="left:${cx(c)}px;top:0;width:${CW}px;text-align:center;font:600 27px/50px 'Alexandria';color:var(--teal-soft)">${days[c]}</div>`;
      for (let r = 0; r < 6; r++) cells += `<div class="cell" style="left:${cx(c)}px;top:${cy(r)}px;width:${CW}px;height:${RH}px"></div>`;
    }
    const cal = add(w, `<div class="mod" style="width:940px;height:1140px"><div class="hd"><div class="ico">${ic.cal}</div><div class="col"><div class="ttl">جدول المقابلات</div><div class="sub">هذا الأسبوع</div></div></div><div class="body">${cells}</div></div>`);
    gsap.set(cal, { x: B + 70, y: 300, rotationY: -7, z: -40 });
    const calB = $('.body', cal);
    const slotDef = [[0, 0, 12.55], [1, 1, 12.68], [2, 0, 12.81], [3, 2, 12.94], [0, 3, 13.07], [1, 1, 13.2, 1], [4, 1, 13.38], [3, 2, 13.52, 3], [2, 4, 13.66], [0, 3, 13.8, 4], [4, 4, 13.9]];
    const slots = slotDef.map(([c, r, t0, clash]) => ({ c, r, t0, clash, e: add(calB, `<div class="slot" style="width:${CW - 12}px;height:${RH - 14}px"><div class="avatar" style="width:50px;height:50px"></div><div class="col" style="gap:8px;flex:1">${sk('90%', 't')}${sk('60%')}</div></div>`) }));
    slots.forEach((s) => { if (s.clash !== undefined) slots[s.clash].hitAt = s.t0 + 0.14; });
    const clashChips = slots.filter((s) => s.clash !== undefined).map((s) => ({ s, e: add(calB, `<div class="chip red-c a" style="font-weight:700;font-size:28px;background:#5a1c1c;left:${cx(s.c) - 30}px;top:${cy(s.r) + RH - 16}px">تعارض!</div>`) }));
    slots.forEach((s) => cue(s.t0 + 0.12, s.clash !== undefined ? 'impact' : 'pop', s.clash !== undefined ? 0.3 : 0.4));

    /* ── C · tracking applicants by hand: spreadsheet + overflowing inbox ── */
    const C = 2 * ST;
    const hC = line(w, 'h2 glowtxt', 'ومتابعة المتقدمين يدويا', 110, `left:${C + 40}px`); reveal(hC, 14.3);
    let us = '';
    const rr = rng(5);
    for (let r = 1; r < 8; r++) for (let c = 0; c < 6; c++) us += `<u data-t="${(14.3 + (r * 6 + c) * 0.045 * (r > 4 ? 1.6 : 0.2)).toFixed(2)}" style="left:${c * 136 + 18}px;top:${r * 62 + 25}px;width:${40 + Math.round(rr() * 70)}px"></u>`;
    const xl = add(w, `<div class="sheetwin" style="width:820px;height:560px"><div class="bar"><i></i><i></i><i></i></div><div class="grid"><div class="hdr"></div>${us}<div class="sel"></div></div></div>`);
    gsap.set(xl, { x: C + 40, y: 300, rotationY: 9, z: -80 });
    const sel = $('.sel', xl), cellsU = $$('u', xl).map((e) => ({ e, t: +e.dataset.t }));
    let mrows = '';
    for (let i = 0; i < 12; i++) mrows += `<div class="mailrow"><div class="dot"></div><div class="col" style="gap:10px;flex:1">${sk((50 + (i * 37) % 40) + '%', '', 'background:#7d9597')}${sk((30 + (i * 53) % 50) + '%')}</div><div style="width:34px;height:34px;color:#8aa0a2">${ic.doc}</div></div>`;
    const inbox = add(w, `<div class="sheetwin" style="width:760px;height:690px"><div class="bar" style="height:84px;direction:rtl;gap:14px;font:700 32px/1 'Alexandria';color:#18373b"><span style="width:38px;height:38px;color:#1b7f88">${ic.mail}</span>البريد الوارد</div>
      <div style="position:absolute;left:0;right:0;top:84px;bottom:0;overflow:hidden">${mrows}</div></div>`);
    gsap.set(inbox, { x: C + 250, y: 760, rotationY: -8, rotation: 2, z: 90 });
    const mails = $$('.mailrow', inbox);
    const badge = add(w, `<div class="badge c" style="transform:translate3d(${C + 215}px,725px,140px)">23</div>`);
    const curC = add(w, `<div class="cursor" style="transform:translate3d(${C + 500}px,640px,160px)">${ic.cursor}</div>`);
    mails.forEach((m, i) => cue(14.45 + i * 0.16, 'pop', 0.35));
    for (let t = 14.4; t < 16.1; t += 0.22) cue(t, 'type', 0.5);

    onFrame((t) => {
      if (t < 9.8 || t >= 16.85) return;
      /* A */
      if (t < 12.8) {
        chA.s.lookX = Math.sin(t * 7.5) * 0.8; chA.s.turn = Math.sin(t * 7.5) * 0.12; chA.update(t);
        let n = 7;
        pages.forEach((p, k) => {
          if (t >= p.f && k < 5) n++;
          const rv = prog(t, p.f - 0.36, p.f - 0.06), u = k < 5 ? prog(t, p.f, p.f + 0.5, 'power2.in') : 0;
          p.scan.style.top = (rv * 650) + 'px'; p.scan.style.opacity = rv > 0 && rv < 1 ? 1 : 0;
          p.stamp.style.transform = `rotate(-14deg) scale(${k < 5 ? back(prog(t, p.f - 0.12, p.f + 0.06)).toFixed(3) : 0})`;
          const lift = prog(t, p.f - 0.42, p.f - 0.3);
          p.e.style.opacity = (1 - prog(t, p.f + 0.34, p.f + 0.5)).toFixed(3);
          p.e.style.transform = `translate3d(${(260 + k * 9 - u * 1150).toFixed(1)}px,${(540 - k * 9 - u * 140).toFixed(1)}px,${(-k * 14 + (k < 5 ? lift * 30 : 0)).toFixed(1)}px) rotateZ(${(-1.5 + k * 1.3 - u * 26).toFixed(2)}deg) rotateY(${(u * 55).toFixed(1)}deg)`;
        });
        nA.textContent = n; barA.style.transform = `scaleX(${(n / 347).toFixed(4)})`;
      }
      /* B */
      if (t > 12 && t < 14.6) {
        for (const s of slots) {
          const p = prog(t, s.t0, s.t0 + 0.22, 'power3.in');
          const clashed = s.clash !== undefined;
          const hit = clashed ? s.t0 + 0.2 : s.hitAt;
          const sh = hit && t >= hit ? Math.exp(-(t - hit) * 7) * Math.sin((t - hit) * 70) * 12 : 0;
          const off = clashed ? 18 : 0;
          s.e.style.opacity = clamp(p * 3);
          s.e.style.transform = `translate(${(cx(s.c) + 6 + off + sh).toFixed(1)}px,${(cy(s.r) + 7 + off - (1 - p) * 260).toFixed(1)}px) rotate(${(clashed ? 4 : 0) + sh * 0.3}deg)`;
          s.e.classList.toggle('bad', !!hit && t >= hit);
        }
        for (const k of clashChips) k.e.style.transform = `scale(${back(prog(t, k.s.t0 + 0.2, k.s.t0 + 0.45)).toFixed(3)})`;
      }
      /* C */
      if (t > 13.9) {
        for (const u of cellsU) u.e.style.opacity = t >= u.t ? 1 : 0;
        const step = Math.max(0, Math.floor((t - 14.3) / 0.22)), sr = 5 + (step * 3) % 3, scol = (step * 5) % 6;
        sel.style.transform = `translate(${scol * 136}px,${sr * 62}px)`;
        let arrived = 0; mails.forEach((m, i) => { if (t >= 14.45 + i * 0.16) arrived++; });
        mails.forEach((m, i) => {
          const t0 = 14.45 + i * 0.16, p = prog(t, t0, t0 + 0.16, 'power2.out');
          let idx = 0; mails.forEach((m2, j) => { if (j > i) idx += prog(t, 14.45 + j * 0.16, 14.45 + j * 0.16 + 0.16, 'power2.out'); });
          m.style.opacity = p; m.style.transform = `translateY(${(idx * 84 - (1 - p) * 84).toFixed(1)}px)`;
          m.style.background = t - t0 < 0.3 ? '#dff5f1' : '#f6faf9';
        });
        const cnt = Math.round(lerp(23, 140, prog(t, 14.3, 16.2, 'power1.in')));
        badge.textContent = cnt > 99 ? '+99' : cnt;
        const bp = 1 + Math.max(0, Math.sin((t - 14.45) / 0.16 * Math.PI * 2)) * 0.1;
        badge.style.transform = `translate3d(${C + 215}px,${725}px,140px) scale(${bp.toFixed(3)})`;
        const cp = (t - 14.2) / 0.55, seg = Math.floor(cp), fr = E.ez('power2.inOut')(clamp((cp - seg) * 1.6));
        const pts = [[C + 500, 640], [C + 700, 1100], [C + 300, 560], [C + 640, 1240], [C + 420, 700], [C + 760, 1000]];
        const a = pts[((seg % 6) + 6) % 6], b = pts[(((seg + 1) % 6) + 6) % 6];
        curC.style.transform = `translate3d(${lerp(a[0], b[0], fr).toFixed(1)}px,${lerp(a[1], b[1], fr).toFixed(1)}px,160px)`;
      }
    });
  })();


  /* ══════════ SCENE 3 · CHAOS → THE CLOCK STOPS → ONE SYSTEM (16.4 – 30) ══════════ */
  (function S3() {
    const sc = scene('e3', 16.4, 30.3), w = sc.world;
    sc.root.insertBefore(E.el(`<div class="floor"></div>`), sc.drift);
    enter(sc.cam, { x: 2600 }, { x: 0 }, 16.4, 0.5, 'power3.out');
    gsap.set(sc.cam, { transformOrigin: '540px 860px' });
    const STOP = 20.0;

    const dl = dial(640, '#f4c95d'); w.appendChild(dl.el);
    gsap.set(dl.el, { x: 220, y: 330, z: -300 });
    const timer = add(w, `<div class="c" style="left:0;width:1080px;top:70px;text-align:center"><div class="lbl" style="font-size:36px;color:#ffb3a8">وقت ضايع</div><div class="num" style="font-size:132px;line-height:1.1;color:#ffd9d2;text-shadow:0 0 44px rgba(255,107,107,.6)"></div></div>`);
    gsap.set(timer, { z: 30 });
    const tnum = $('.num', timer);

    const desk = add(w, `<div class="e-desk c" style="top:1660px"></div>`); gsap.set(desk, { z: 10 });
    const ch = Char.bust({ variant: 'manager', seed: 2.9 }); w.appendChild(ch.el);
    gsap.set(ch.el, { x: 165, y: 760, scale: 1.25, transformOrigin: '0 0' });
    const S = ch.s;
    Object.assign(S, { brow: -1, sweat: 1, smile: -0.5, lookX: -0.6, tilt: -2, glow: 0.15 });
    tl.to(S, { lookX: 0.75, turn: 0.4, tilt: 2, duration: 0.5, ease: 'sine.inOut' }, 16.9)
      .to(S, { lookX: -0.75, turn: -0.45, tilt: -3, duration: 0.5, ease: 'sine.inOut' }, 17.6)
      .to(S, { lookX: 0.6, lookY: 0.4, turn: 0.35, tilt: 3, duration: 0.5, ease: 'sine.inOut' }, 18.3)
      .to(S, { lookX: -0.55, lookY: -0.3, turn: -0.3, bob: 10, open: 0.3, duration: 0.5, ease: 'sine.inOut' }, 19.0)
      .to(S, { eye: 1.32, brow: 0.9, lookX: 0, lookY: 0, turn: 0, tilt: 0, bob: 0, open: 0.4, duration: 0.2, ease: 'power3.out' }, STOP)
      .to(S, { eye: 1, brow: 0.2, open: 0, smile: -0.1, sweat: 0, tilt: -3, duration: 0.8, ease: 'sine.inOut' }, 20.9)
      .to(S, { lookY: -0.95, brow: 0.85, eye: 1.2, smile: 0.25, glow: 0.75, tilt: 0, duration: 0.9, ease: 'power2.inOut' }, 23.2)
      .to(S, { smile: 0.85, open: 0.3, brow: 1, duration: 0.3, ease: 'power3.out' }, 26.0)
      .to(S, { open: 0.05, lookX: 0.3, turn: 0.2, duration: 1.4, ease: 'sine.inOut' }, 27.2);
    tl.to(ch.el, { x: 270, y: 1300, scale: 0.9, duration: 1.3, ease: 'power3.inOut' }, 22.5);
    tl.to(desk, { y: 500, duration: 1.0, ease: 'power2.in' }, 22.5);

    /* the pile of disconnected tools */
    const mini = (kind) => kind === 'sheet'
      ? `<div class="sheetwin c" style="width:300px;height:230px"><div class="bar" style="height:36px"><i></i><i></i><i></i></div><div class="grid" style="top:36px;background-size:60px 32px"><div class="hdr" style="height:32px"></div></div></div>`
      : UI.win(kind, kind === 'cv' ? 230 : 280, kind === 'cv' ? 290 : 230, 'متابعة');
    const pile = [[40, 400, -8, -200, 'sheet', 1.3], [700, 380, 7, -220, 'mail', 1.25], [-60, 730, 6, -120, 'cv', 1.25], [820, 720, -6, -140, 'job', 1.2], [-10, 1100, -10, 60, 'mail', 1.2], [790, 1090, 9, 70, 'sheet', 1.2],
      [250, 270, 3, -330, 'job', 1.2], [560, 250, -5, -380, 'cv', 1.15], [-120, 1420, 8, 120, 'job', 1.3], [830, 1430, -9, 130, 'cv', 1.2], [330, 1560, 4, 150, 'mail', 1.25], [-170, 190, 5, -430, 'mail', 1.3],
      [930, 170, -7, -450, 'sheet', 1.3], [150, 590, -3, -260, 'cv', 1.1], [690, 590, 5, -280, 'job', 1.1], [560, 1600, -6, 160, 'sheet', 1.2]].map(([x, y, rot, z, kind, s], i) => {
      const e = add(w, mini(kind));
      if (z > 0) e.style.filter = 'blur(3px)';
      const at = 16.6 + i * 0.2;
      cue(at + 0.3, 'pop', 0.45 + i * 0.02);
      return { e, x, y, rot, z, s, at, dir: i % 2 ? 1 : -1, i };
    });
    for (let t = 16.5; t < STOP; t += t < 18.5 ? 0.25 : 0.125) cue(t, 'tick', 0.4 + (t - 16.4) * 0.16);
    cue(17.9, 'riser', 0.8, { dur: 2.1 });
    cue(19.55, 'freeze', 1);
    flash(STOP, { color: '255,255,255', a: 0.32, dur: 0.5, y: 800 });
    tl.to([timer, dl.el], { opacity: 0.4, duration: 0.5 }, 20.2).to([timer, dl.el], { opacity: 0, duration: 0.6, ease: 'power2.in' }, 22.0);

    /* words */
    const t0 = add(w, `<div class="c h1" style="left:0;width:1080px;top:300px;font-size:150px;text-shadow:0 8px 40px rgba(0,0,0,.95),0 0 60px rgba(0,0,0,.8)">طيب..</div>`);
    gsap.set(t0, { z: 60, transformOrigin: '50% 50%' });
    enter(t0, { scale: 0.6, opacity: 0 }, { scale: 1, opacity: 1 }, 20.8, 0.4, 'back.out(1.8)');
    out(t0, 21.8, 0.3, { y: -50 });
    cue(20.8, 'pop', 0.7);
    const t1 = line(w, 'h3 glowtxt', 'وش لو صارت رحلة التوظيف كلها', 150, 'font-size:54px');
    const t2 = line(w, 'h2 tealtxt', 'في نظام واحد؟', 236, 'font-size:76px');
    reveal(t1, 22.05, { stagger: 0.36 }); reveal(t2, 24.15, { stagger: 0.34 });
    out([t1, t2], 25.7, 0.25, { y: -30 });
    const big = add(w, `<div class="c" style="left:0;width:1080px;top:110px;text-align:center"><div class="gold" style="font:800 164px/1.3 'Alexandria'">نظام واحد</div></div>`);
    gsap.set(big, { z: 120, transformOrigin: '50% 50%' });
    enter(big, { scale: 2.2, opacity: 0 }, { scale: 1, opacity: 1 }, 25.9, 0.22, 'power3.in');
    tl.to(big, { scale: 1.05, duration: 3.4, ease: 'sine.inOut' }, 26.15);
    tl.fromTo(sc.shake, { v: 34 }, { v: 0, duration: 0.6, ease: 'power2.out', immediateRender: false }, 26.1);
    flash(26.1, { color: '255,225,150', y: 300, a: 0.8 });
    cue(26.1, 'impact', 1); cue(23.6, 'riser', 0.9, { dur: 2.4 });

    /* particles: every scattered tool becomes data and flows into one place */
    particles({ n: 1500, seed: 31, t0: 22.0, t1: 24.6, spread: 0.45, swirl: 320, size: 3.2, gold: 0.18, hold: 0.15, fadeOut: 0.5,
      from: (i, r) => { const p = pile[i % pile.length]; return { x: p.x + 60 + r() * 280, y: p.y + r() * 280 }; },
      to: (i, r) => { const e = r(); return e < 0.5 ? { x: 110 + r() * 860, y: 400 + r() * 900 } : e < 0.75 ? { x: r() < 0.5 ? 100 : 980, y: 390 + r() * 920 } : { x: 100 + r() * 880, y: r() < 0.5 ? 390 : 1310 }; } });
    cue(22.0, 'sparkle', 1); cue(22.05, 'whoosh', 0.6);

    /* the dashboard: exploded layers that snap into one product */
    const dash = add(w, `<div class="p3"></div>`);
    gsap.set(dash, { transformOrigin: '540px 860px', rotationY: -30, rotationX: 7 });
    tl.to(dash, { rotationY: 9, rotationX: 2, duration: 6.4, ease: 'sine.inOut' }, 23.4);
    const L = [];
    const layer = (html, x, y, z, at) => { const e = add(dash, html); L.push({ e, x, y, z, at }); return e; };
    const shell = layer(`<div class="mod" style="width:900px;height:950px"><div class="hd"><div class="ico">${ic.grid}</div><div class="col" style="flex:1"><div class="ttl">لوحة التوظيف</div><div class="sub">كل الرحلة في مكان واحد</div></div>${tag()}</div><div class="sheen"><i></i></div></div>`, 90, 380, -70, 23.4);
    const side = layer(`<div class="panel" style="position:absolute;left:0;top:0;width:128px;height:740px;border-radius:30px;display:flex;flex-direction:column;align-items:center;gap:30px;padding-top:34px">
      ${['brief', 'users', 'filter', 'mic', 'flag', 'chart'].map((n, i) => `<div style="width:76px;height:76px;border-radius:22px;display:grid;place-items:center;${i === 0 ? 'background:linear-gradient(180deg,#7df3e8,#2ee6d6)' : 'background:rgba(255,255,255,.06)'}">${icon(n, 42, i === 0 ? '#04282c' : '#9af7ee')}</div>`).join('')}</div>`, 824, 540, 50, 23.9);
    const kp = [['وظائف نشطة', 12], ['متقدمون', 347], ['مقابلات', 28]].map(([lb, v], i) => ({ v, e: layer(`<div class="panel kpi" style="position:absolute;left:0;top:0;width:206px;height:170px;border-radius:26px;padding:20px 22px"><div class="lbl" style="font-size:25px">${lb}</div><div class="num"></div></div>`, 578 - i * 224, 540, 80 + i * 10, 24.1 + i * 0.14) }));
    const pipe = layer(`<div class="panel" style="position:absolute;left:0;top:0;width:654px;height:262px;border-radius:28px;padding:22px 24px"><div class="ttl" style="font-size:28px">مراحل التوظيف</div>
      <div style="position:absolute;left:24px;right:24px;top:76px;bottom:22px">${[0, 1, 2, 3].map((c) => `<div class="kcol" style="right:${c * 154}px;width:144px"></div>`).join('')}
      ${[[0, 0], [0, 1], [1, 0], [2, 0], [1, 1]].map(([c, r], i) => `<div class="kcard" data-i="${i}" style="width:128px;height:66px"><div class="avatar" style="width:40px;height:40px"></div><div class="col" style="gap:6px;flex:1">${sk('90%', 't')}${sk('60%')}</div></div>`).join('')}</div></div>`, 130, 734, 60, 24.55);
    const list = layer(`<div class="panel" style="position:absolute;left:0;top:0;width:654px;height:282px;border-radius:28px;padding:22px 24px"><div class="ttl" style="font-size:28px">أفضل المرشحين</div>
      ${[0, 1].map((i) => `<div class="lrow" style="left:24px;right:24px;top:${76 + i * 98}px;height:86px"><div class="avatar ${i === 0 ? 'gold-a' : ''}" style="width:60px;height:60px"></div><div class="col" style="gap:9px;flex:1">${sk('56%', 't', 'height:12px')}${sk('36%', '', 'height:10px')}</div>${UI.ring(i === 0 ? '#f4c95d' : '#2ee6d6', 70)}</div>`).join('')}</div>`, 130, 1018, 70, 24.85);
    L.forEach((l, i) => {
      enter(l.e, { x: l.x + (i % 2 ? 260 : -260), y: l.y + 120, z: 620, rotationX: i % 2 ? 40 : -40, rotationY: i % 2 ? -50 : 50, opacity: 0 }, { x: l.x, y: l.y, z: l.z, rotationX: 0, rotationY: 0, opacity: 1 }, l.at, 0.75, 'back.out(1.25)');
      if (i) tl.to(l.e, { z: 14, duration: 0.2, ease: 'power3.in' }, 25.92);
      cue(l.at + 0.45, i ? 'pop' : 'swish', 0.6);
    });
    tl.fromTo($('.sheen i', shell), { left: '-40%' }, { left: '120%', duration: 1.2, ease: 'power2.inOut', immediateRender: false }, 26.2);
    const kcards = $$('.kcard', pipe), rings = $$('.ring', list);
    const kpos = [[[0, 0], [1, 0]], [[0, 1], [0, 0]], [[1, 0], [2, 0]], [[2, 0], [3, 0]], [[1, 1], [1, 0]]];
    cue(27.2, 'swish', 0.5); cue(28.0, 'swish', 0.5); cue(28.6, 'ding', 0.5);

    /* push through the dashboard into the product */
    tl.to(sc.cam, { scale: 4.2, y: -420, duration: 0.7, ease: 'power3.in' }, 29.5);
    tl.to(big, { opacity: 0, duration: 0.3 }, 29.5);
    cue(29.45, 'whoosh', 1);
    flash(29.95, { color: '160,255,245', a: 0.7, dur: 0.6 });

    onFrame((t) => {
      if (t < 16.4 || t >= 30.3) return;
      const c = t < 19.85 ? t : Math.min(STOP, 19.85 + 0.15 * outC((t - 19.85) / 0.15));
      ch.update(t);
      const run = c - 16.4;
      dl.set(run * 1.4 + run * run * 0.5 + (t > STOP ? Math.exp(-(t - STOP) * 9) * Math.sin((t - STOP) * 40) * 0.004 : 0));
      const secs = Math.floor(Math.pow(Math.max(0, run), 2.2) * 2200);
      const pad = (n) => String(n).padStart(2, '0');
      tnum.textContent = `${pad(Math.floor(secs / 3600))}:${pad(Math.floor(secs / 60) % 60)}:${pad(secs % 60)}`;
      if (t < 23.2) for (const p of pile) {
        const a = clamp((c - p.at) / 0.42), e = back(a), fade = prog(t, 22.0 + p.i * 0.05, 22.5 + p.i * 0.05, 'power2.in');
        const jit = Math.sin(c * 17 + p.i) * 2.5 * (t < STOP ? 1 : 0);
        p.e.style.opacity = (clamp(a * 4) * (1 - fade)).toFixed(3);
        p.e.style.transform = `translate3d(${(p.x + p.dir * (1 - e) * 1100 + jit).toFixed(1)}px,${(p.y - (1 - e) * 260).toFixed(1)}px,${p.z}px) rotateZ(${(p.rot + (1 - e) * p.dir * 70).toFixed(2)}deg) scale(${(p.s * (1 - fade * 0.3)).toFixed(3)})`;
      } else for (const p of pile) p.e.style.opacity = 0;
      if (t > 23.5) {
        kp.forEach((k, i) => { $('.num', k.e).textContent = Math.round(k.v * prog(t, 24.6 + i * 0.15, 26.4 + i * 0.15, 'power2.out')); });
        kcards.forEach((k, i) => {
          const [a, b] = kpos[i], mv = prog(t, 27.0 + i * 0.4, 27.45 + i * 0.4, 'power3.inOut');
          const col = lerp(a[0], b[0], mv), row = lerp(a[1], b[1], mv);
          k.style.transform = `translate(${(606 - 136 - col * 154 + 8).toFixed(1)}px,${(10 + row * 76 - Math.sin(mv * Math.PI) * 22).toFixed(1)}px)`;
        });
        rings.forEach((rg, i) => UI.setRing(rg, [0.94, 0.88][i] * prog(t, 25.6 + i * 0.25, 27.2 + i * 0.25, 'power2.out')));
      }
    });
  })();


  /* ══════════ SCENE 4 · NINE FEATURES ON ONE CONTINUOUS BOARD (30 – 58) ══════════ */
  (function S4() {
    const sc = scene('e4', 30, 58), w = sc.world;
    sc.driftAmt = 0.6;
    const T0 = 30, D = 3, PX = 1100, PY = 1440, AX = 540, AY = 1000;
    const ORDER = [[2, 0], [1, 0], [0, 0], [0, 1], [1, 1], [2, 1], [2, 2], [1, 2], [0, 2]];   // RTL snake
    const rig = add(w, `<div class="p3"></div>`); rig.style.transformOrigin = `${AX}px ${AY}px`;
    const board = add(rig, `<div class="p3"></div>`);
    const mods = [];
    function mod(i, icn, title, sub, body, hdExtra = '') {
      const [c, r] = ORDER[i];
      const e = add(board, `<div class="mod" style="width:900px;height:1240px"><div class="hd"><div class="ico">${ic[icn]}</div><div class="col" style="flex:1"><div class="ttl">${title}</div><div class="sub">${sub}</div></div>${hdExtra}</div><div class="body">${body}</div><div class="sheen"><i></i></div></div>`);
      gsap.set(e, { x: c * PX, y: r * PY });
      tl.fromTo($('.sheen i', e), { left: '-40%' }, { left: '120%', duration: 1.0, ease: 'power2.inOut', immediateRender: false }, T0 + i * D + 0.25);
      mods.push({ e, c, r });
      return $('.body', e);
    }
    /* floating accent above a module (gives parallax when the camera tilts) */
    function accent(i, html, x, y, z = 90) { const [c, r] = ORDER[i]; const e = add(board, html); gsap.set(e, { x: c * PX + x, y: r * PY + y, z }); return e; }
    const T = (i) => T0 + i * D;
    const chk = (size = 44) => UI.check(size);
    const bar = (cls = '') => `<div class="bar-bg ${cls}"><i></i></div>`;
    const grow = (el, at, dur = 0.7, to = 1) => enter(el, { scaleX: 0 }, { scaleX: to }, at, dur, 'power3.out');

    /* ── 1 · create & publish a job ── */
    {
      const A = T(0);
      const b = mod(0, 'brief', 'إعلان وظيفة جديد', 'إنشاء ونشر', `
        <div class="field" style="top:0"><div class="fl">المسمى الوظيفي</div><div class="fi"><span data-k="t1"></span></div></div>
        <div class="field" style="top:150px"><div class="fl">المدينة</div><div class="fi">${icon('pin', 34)}<span data-k="t2"></span></div></div>
        <div class="field" style="top:300px"><div class="fl">نوع الدوام</div><div class="row" style="margin-top:14px;gap:14px"><span class="chip" data-k="ft">دوام كامل</span><span class="chip">دوام جزئي</span><span class="chip">عن بعد</span></div></div>
        <div class="field" style="top:440px"><div class="fl">المهارات المطلوبة</div><div class="row" style="margin-top:14px;gap:14px"><span class="chip gold-c sk1">Python</span><span class="chip gold-c sk1">قواعد البيانات</span><span class="chip gold-c sk1">العمل الجماعي</span></div></div>
        <div class="a row" style="left:0;right:0;top:600px;height:100px;justify-content:space-between;border-top:1.5px solid rgba(125,243,232,.16);padding-top:10px"><div class="ttl" style="font-size:32px">حالة الإعلان</div>
          <div style="position:relative;width:230px;height:60px"><span class="chip gold-c a st0" style="left:0;top:0">مسودة</span><span class="chip green-c a st1" style="left:0;top:0;font-weight:700">${icon('check', 26, '#a8f5cf')}منشورة</span></div></div>
        <div class="a ringp" style="left:206px;top:760px;width:400px;height:110px;border-radius:55px;border:3px solid #f4c95d"></div>
        <div class="a ringp" style="left:206px;top:760px;width:400px;height:110px;border-radius:55px;border:3px solid #f4c95d"></div>
        <div class="btn gold-b a pub" style="left:0;right:0;top:750px;height:130px;font-size:48px">${icon('send', 46, '#04282c')}<span>نشر الوظيفة</span></div>
        <div class="a row" style="left:0;right:0;top:920px;gap:16px;justify-content:center"><span class="chip ch1">${icon('grid', 26)}صفحة الوظائف</span><span class="chip ch1">${icon('users', 26)}قاعدة المواهب</span><span class="chip ch1">${icon('bell', 26)}تنبيه المهتمين</span></div>
        <div class="cursor cur1">${ic.cursor}</div>`);
      UI.type($('[data-k="t1"]', b), 'مهندس برمجيات', A + 0.25, A + 0.85);
      UI.type($('[data-k="t2"]', b), 'الرياض', A + 0.9, A + 1.15);
      for (let t = A + 0.25; t < A + 1.15; t += 0.11) cue(t, 'type', 0.5);
      const ft = $('[data-k="ft"]', b);
      onFrame((t) => ft.classList.toggle('solid', t >= A + 1.3));
      cue(A + 1.3, 'click', 0.7);
      $$('.sk1', b).forEach((e, i) => { pop(e, A + 1.45 + i * 0.14, 0.4); cue(A + 1.45 + i * 0.14, 'pop', 0.45); });
      const pub = $('.pub', b);
      tl.to(pub, { scale: 0.94, duration: 0.07, ease: 'power2.out' }, A + 2.02).to(pub, { scale: 1, duration: 0.3, ease: 'back.out(2.5)' }, A + 2.09);
      cue(A + 2.05, 'click', 1); cue(A + 2.12, 'ding', 0.9);
      gsap.set($$('.ringp', b), { opacity: 0 });
      $$('.ringp', b).forEach((e, i) => { tl.fromTo(e, { scale: 1, opacity: 0.9 }, { scale: 1.5 + i * 0.45, opacity: 0, duration: 0.7 + i * 0.15, ease: 'power2.out', immediateRender: false }, A + 2.08); });
      tl.to($('.st0', b), { opacity: 0, scale: 0.6, duration: 0.15 }, A + 2.1); pop($('.st1', b), A + 2.14, 0.45);
      $$('.ch1', b).forEach((e, i) => pop(e, A + 2.25 + i * 0.1, 0.4));
      const cur = $('.cur1', b);
      enter(cur, { x: 120, y: 520, opacity: 0 }, { x: 560, y: 365, opacity: 1 }, A + 0.95, 0.35, 'power2.inOut');
      tl.to(cur, { x: 420, y: 830, duration: 0.5, ease: 'power2.inOut' }, A + 1.5);
      const toast = accent(0, `<div class="panel gold-edge c row" style="height:96px;padding:0 28px;gap:16px;border-radius:26px">${chk(46)}<div class="ttl" style="font-size:32px;white-space:nowrap">تم نشر الإعلان</div></div>`, -40, 1010, 110);
      pop(toast, A + 2.2, 0.5);
    }

    /* ── 2 · applicants arrive into one unified system ── */
    {
      const A = T(1);
      const roles = ['خبرة 5 سنوات', 'خبرة 3 سنوات', 'خبرة 7 سنوات', 'حديث تخرج', 'خبرة 4 سنوات', 'خبرة 6 سنوات', 'خبرة سنتين'];
      const src = ['نموذج التقديم', 'رفع مباشر', 'نموذج التقديم', 'قاعدة المواهب', 'نموذج التقديم', 'رفع مباشر', 'نموذج التقديم'];
      const b = mod(1, 'users', 'المتقدمون', 'مهندس برمجيات · الرياض', `
        <div class="a row" style="left:0;right:0;top:0;height:150px;justify-content:space-between">
          <div class="col"><div class="lbl" style="font-size:28px">إجمالي المتقدمين</div><div class="num cnt2" style="font-size:96px;line-height:1.1;color:#fff;text-shadow:0 0 30px rgba(46,230,214,.5)"></div></div>
          <div class="col" style="gap:10px;align-items:flex-start"><span class="chip solid">${icon('check', 24, '#04282c')}بيانات موحدة</span><span class="chip">كل المصادر في قائمة واحدة</span></div></div>
        <div class="a" style="left:0;right:0;top:186px;bottom:0;overflow:hidden">${roles.map((rl, i) => `<div class="lrow rw2"><div class="avatar"></div><div class="col" style="gap:8px;flex:1">${sk((38 + (i * 29) % 30) + '%', 't', 'height:14px')}<div class="rl">${rl}</div></div><span class="chip ${src[i] === 'قاعدة المواهب' ? 'gold-c' : ''}" style="font-size:22px">${src[i]}</span></div>`).join('')}</div>`, tag());
      const rows = $$('.rw2', b), cnt = $('.cnt2', b);
      const at = (i) => A + 0.3 + i * 0.3;
      rows.forEach((r, i) => cue(at(i), 'pop', 0.5));
      onFrame((t) => {
        if (t < A - 1 || t > A + 4.5) return;
        let n = 0;
        rows.forEach((r, i) => {
          const p = prog(t, at(i), at(i) + 0.22, 'power3.out'); if (t >= at(i)) n++;
          let idx = 0; rows.forEach((r2, j) => { if (j > i) idx += prog(t, at(j), at(j) + 0.22, 'power3.out'); });
          r.style.opacity = p; r.style.transform = `translateY(${(idx * 118 - (1 - p) * 118).toFixed(1)}px)`;
          const fresh = t >= at(i) && t - at(i) < 0.35;
          r.style.borderColor = fresh ? 'rgba(125,243,232,.9)' : 'rgba(125,243,232,.18)'; r.style.background = fresh ? 'rgba(46,230,214,.16)' : 'rgba(255,255,255,.055)';
        });
        cnt.textContent = 340 + n;
      });
    }

    /* ── 3 · bulk CV upload → the company's own talent pool ── */
    {
      const A = T(2);
      let tiles = '';
      for (let k = 0; k < 12; k++) tiles += `<div class="tile tl3" style="width:188px;height:170px;transform:translate(${812 - (k % 4 + 1) * 188 - (k % 4) * 20}px,${Math.floor(k / 4) * 190}px)"><div class="avatar" style="width:62px;height:62px"></div>${sk('60%', 't')}${sk('40%')}</div>`;
      const b = mod(2, 'up', 'رفع السير الذاتية بالجملة', 'وبناء قاعدة مواهب خاصة بالمنشأة', `
        <div class="a" style="left:0;right:0;top:0;height:290px;border-radius:30px;border:3px dashed rgba(125,243,232,.5);background:rgba(46,230,214,.05);display:flex;flex-direction:column;align-items:center;justify-content:center;gap:12px">
          ${icon('up', 70)}<div class="ttl" style="font-size:32px">اسحب السير الذاتية هنا</div><div class="sub" style="direction:ltr">PDF · DOCX</div></div>
        ${[0, 1, 2, 3, 4, 5].map((k) => `<div class="paper a fl3" style="left:${90 + k * 112}px;top:70px;width:96px;height:124px;padding:12px;border-radius:10px">${sk('70%', 't', 'height:7px')}<div class="col" style="gap:7px;margin-top:10px">${sk('100%', '', 'height:5px')}${sk('80%', '', 'height:5px')}${sk('90%', '', 'height:5px')}${sk('50%', '', 'height:5px')}</div></div>`).join('')}
        <div class="a" style="left:0;right:0;top:318px"><div class="row" style="justify-content:space-between"><div class="lbl" style="font-size:27px">قراءة وتحليل السير الذاتية</div><div class="num pc3" style="font-size:34px;color:var(--teal-soft)"></div></div><div style="margin-top:10px">${bar()}</div></div>
        <div class="a row" style="left:0;right:0;top:412px;justify-content:space-between"><div class="ttl" style="font-size:34px">قاعدة المواهب</div><span class="chip gold-c">خاصة بالمنشأة</span></div>
        <div class="a" style="left:0;top:486px">${tiles}</div>`);
      const files = $$('.fl3', b), pc = $('.pc3', b), fill = $('.bar-bg i', b);
      files.forEach((f, k) => { enter(f, { y: -520, rotation: (k % 2 ? 1 : -1) * 40, opacity: 0 }, { y: 0, rotation: (k - 2.5) * 5, opacity: 1 }, A + 0.15 + k * 0.08, 0.5, 'bounce.out'); out(f, A + 1.35 + k * 0.05, 0.3, { y: 160, scale: 0.4 }); });
      cue(A + 0.2, 'swish', 0.8); cue(A + 0.55, 'pop', 0.7); cue(A + 0.75, 'scan', 0.6, { dur: 0.85 });
      grow(fill, A + 0.75, 0.85);
      onFrame((t) => { pc.textContent = Math.round(prog(t, A + 0.75, A + 1.6, 'power3.out') * 100) + '%'; });
      $$('.tl3', b).forEach((e, k) => {
        const inner = e;   // tiles carry their grid transform inline, so animate opacity + inner pop via scale on children
        gsap.set(inner.children, { scale: 0.3 }); gsap.set(inner, { opacity: 0 });
        tl.to(inner, { opacity: 1, duration: 0.25 }, A + 1.4 + k * 0.08);
        tl.to(inner.children, { scale: 1, duration: 0.4, ease: 'back.out(2)' }, A + 1.4 + k * 0.08);
        if (k % 2 === 0) cue(A + 1.4 + k * 0.08, 'pop', 0.4);
      });
      cue(A + 2.4, 'ding', 0.7);
    }

    /* ── 4 · smart search & sorting of candidates ── */
    {
      const A = T(3);
      const HIT = [1, 4, 6, 9, 10];
      let tiles = '';
      for (let k = 0; k < 12; k++) tiles += `<div class="tile tl4" style="width:257px;height:176px"><div class="row" style="gap:14px;width:100%;padding:0 22px"><div class="avatar" style="width:60px;height:60px"></div><div class="col" style="gap:9px;flex:1">${sk((60 + (k * 13) % 30) + '%', 't')}${sk((35 + (k * 17) % 30) + '%')}</div></div><span class="chip solid mt4" style="font-size:21px;padding:4px 16px">مطابق</span></div>`;
      const b = mod(3, 'search', 'البحث الذكي عن المرشحين', 'فرز حسب المؤهلات والخبرات', `
        <div class="a row" style="left:0;right:0;top:0;height:96px;border-radius:48px;background:rgba(0,0,0,.3);border:2px solid rgba(125,243,232,.45);padding:0 30px;gap:16px;font:600 34px/1 'Alexandria';color:#fff">${icon('search', 40)}<span data-k="q"></span></div>
        <div class="a row" style="left:0;right:0;top:120px;gap:14px">${icon('filter', 36)}<span class="chip gold-c c4">خبرة +5 سنوات</span><span class="chip gold-c c4">Python</span><span class="chip gold-c c4">بكالوريوس</span></div>
        <div class="a row" style="left:0;right:0;top:196px;justify-content:space-between"><div class="lbl" style="font-size:28px">النتائج</div><div style="font:800 40px/1.2 'Alexandria';color:#fff"><span class="num n4"></span> <span style="font-size:27px;color:var(--mute)">مرشح</span></div></div>
        <div class="a" style="left:0;top:268px">${tiles}</div>`);
      UI.type($('[data-k="q"]', b), 'مهندس برمجيات', A + 0.2, A + 0.75);
      for (let t = A + 0.2; t < A + 0.75; t += 0.11) cue(t, 'type', 0.5);
      $$('.c4', b).forEach((e, i) => { pop(e, A + 0.85 + i * 0.15, 0.4); cue(A + 0.85 + i * 0.15, 'pop', 0.5); });
      const ts = $$('.tl4', b), n4 = $('.n4', b);
      const slot = (s) => [812 - (s % 3 + 1) * 257 - (s % 3) * 20, Math.floor(s / 3) * 196];
      const dest = []; let h = 0, m = HIT.length;
      for (let k = 0; k < 12; k++) dest[k] = HIT.includes(k) ? h++ : m++;
      cue(A + 1.4, 'swish', 0.9); cue(A + 2.1, 'ding', 0.8);
      onFrame((t) => {
        if (t < A - 1 || t > A + 4.5) return;
        const f = prog(t, A + 1.4, A + 2.1, 'power3.inOut');
        ts.forEach((e, k) => {
          const a = slot(k), d = slot(dest[k]), hit = HIT.includes(k);
          e.style.transform = `translate(${lerp(a[0], d[0], f).toFixed(1)}px,${(lerp(a[1], d[1], f) - Math.sin(f * Math.PI) * (hit ? 26 : 0)).toFixed(1)}px) scale(${(hit ? 1 : 1 - f * 0.06).toFixed(3)})`;
          e.style.opacity = hit ? 1 : 1 - f * 0.78;
          e.classList.toggle('hit', hit && f > 0.3);
          e.querySelector('.mt4').style.opacity = hit ? prog(t, A + 1.9, A + 2.2) : 0;
        });
        n4.textContent = Math.round(lerp(12, 5, prog(t, A + 1.4, A + 2.0)));
      });
    }

    /* ── 5 · candidate ↔ requirements match analysis ── */
    {
      const A = T(4);
      const req = [['سنوات الخبرة', 0.96], ['المهارات التقنية', 0.9], ['المؤهل العلمي', 1], ['اللغات', 0.82]];
      const b = mod(4, 'chart', 'تحليل المطابقة', 'المرشح مقابل متطلبات الوظيفة', `
        <div class="a row" style="left:0;right:0;top:0;height:170px;border-radius:28px;background:rgba(255,255,255,.05);border:1px solid rgba(244,201,93,.4);padding:0 26px;gap:22px">
          <div class="avatar gold-a" style="width:96px;height:96px"></div><div class="col" style="gap:12px;flex:1">${sk('58%', 'g', 'height:16px')}<div class="rl" style="font:400 26px/1.3 'Plex';color:var(--mute)">مرشح · مهندس برمجيات</div></div>${UI.ring('#f4c95d', 132)}</div>
        ${req.map(([lb], i) => `<div class="a" style="left:0;right:0;top:${204 + i * 106}px"><div class="row" style="justify-content:space-between"><div class="ttl" style="font-size:29px">${lb}</div><div class="ck5">${chk(40)}</div></div><div style="margin-top:10px">${bar(i === 2 ? 'g' : '')}</div></div>`).join('')}
        <div class="a row" style="left:0;right:0;top:636px;justify-content:space-between;border-top:1.5px solid rgba(125,243,232,.16);padding-top:14px"><div class="ttl" style="font-size:32px">ترتيب المرشحين حسب المطابقة</div></div>
        ${[0, 1, 2].map((i) => `<div class="tile a cd5 ${i === 0 ? 'hit' : ''}" style="left:${812 - (i + 1) * 257 - i * 20}px;top:716px;width:257px;height:320px;${i === 0 ? 'border-color:#ffe7a8;box-shadow:0 0 40px rgba(244,201,93,.4);background:rgba(244,201,93,.1)' : ''}"><div class="avatar ${i === 0 ? 'gold-a' : ''}" style="width:70px;height:70px"></div>${sk('56%', i === 0 ? 'g' : 't')}${UI.ring(i === 0 ? '#f4c95d' : '#2ee6d6', 116)}</div>`).join('')}`, tag());
      const fills = $$('.bar-bg i', b), cks = $$('.ck5', b), cards = $$('.cd5', b), rings = $$('.ring', b);
      fills.forEach((f, i) => { grow(f, A + 0.3 + i * 0.22, 0.7, req[i][1]); pop(cks[i], A + 0.95 + i * 0.22, 0.35); cue(A + 0.95 + i * 0.22, 'pop', 0.45); });
      cards.forEach((c, i) => { pop(c, A + 1.5 + i * 0.14, 0.45); cue(A + 1.5 + i * 0.14, 'pop', 0.55); });
      cue(A + 0.3, 'scan', 0.6, { dur: 1.2 }); cue(A + 2.5, 'ding', 0.9);
      onFrame((t) => {
        if (t < A - 1 || t > A + 4.5) return;
        UI.setRing(rings[0], 0.94 * prog(t, A + 0.5, A + 1.9, 'power2.out'));
        [0.94, 0.88, 0.76].forEach((v, i) => UI.setRing(rings[i + 1], v * prog(t, A + 1.7 + i * 0.12, A + 2.6 + i * 0.12, 'power2.out')));
      });
    }

    /* ── 6 · AI-assisted interviews (when the employer enables them) ── */
    {
      const A = T(5);
      const sc6 = ['التواصل', 'حل المشكلات', 'الملاءمة للدور'], val = [0.88, 0.92, 0.84];
      let bars = ''; for (let k = 0; k < 30; k++) bars += '<i></i>';
      const b = mod(5, 'mic', 'المقابلة الذكية', 'مدعومة بالذكاء الاصطناعي', `
        <div class="a row" style="left:0;right:0;top:0;height:96px;border-radius:26px;background:rgba(255,255,255,.05);border:1px solid rgba(125,243,232,.2);padding:0 24px;justify-content:space-between">
          <div class="row" style="gap:16px"><div class="toggle" style="transform:scale(.8)"><i></i></div><div class="ttl" style="font-size:30px">تفعيل المقابلة الذكية</div></div><span class="tag-ex" style="font-size:22px">عند تفعيلها من المنشأة</span></div>
        <div class="orb a ob6" style="left:331px;top:150px;width:150px;height:150px"></div>
        <div class="bubble them a bb6" style="right:0;left:auto;top:340px;max-width:812px;font-size:32px"><span data-k="q6"></span></div>
        <div class="a" style="left:0;right:0;top:468px;height:200px;border-radius:28px;background:rgba(0,0,0,.25);border:1px solid rgba(125,243,232,.2)">
          <div class="row a" style="right:24px;top:16px;gap:10px">${icon('mic', 30)}<span class="lbl" style="font-size:25px">إجابة المرشح</span></div><div class="wave a wv6" style="left:0;right:0;top:62px;height:124px">${bars}</div></div>
        <div class="a row" style="left:0;right:0;top:696px;justify-content:space-between"><div class="ttl" style="font-size:32px">تقييم أولي للمقابلة</div>${tag()}</div>
        ${sc6.map((lb, i) => `<div class="a" style="left:0;right:0;top:${770 + i * 92}px"><div class="row" style="justify-content:space-between"><div class="lbl" style="font-size:27px;color:#d8efed">${lb}</div><div class="num n6" style="font-size:28px;color:var(--teal-soft)"></div></div><div style="margin-top:8px">${bar()}</div></div>`).join('')}`);
      const tg = $('.toggle', b), knob = $('.toggle i', b), orb = $('.ob6', b), wave = $$('.wv6 i', b), fills = $$('.bar-bg i', b), ns = $$('.n6', b);
      tl.to(knob, { x: 62, backgroundColor: '#ffffff', duration: 0.25, ease: 'power3.out' }, A + 0.3).to(tg, { backgroundColor: '#17b5a8', borderColor: '#7df3e8', duration: 0.25 }, A + 0.3);
      cue(A + 0.3, 'click', 0.9); cue(A + 0.45, 'sparkle', 0.7);
      pop(orb, A + 0.4, 0.5); pop($('.bb6', b), A + 0.6, 0.4, { from: { transformOrigin: '100% 0%' } });
      UI.type($('[data-k="q6"]', b), 'حدثنا عن مشروع قدته مؤخرا', A + 0.7, A + 1.35, false);
      fills.forEach((f, i) => { grow(f, A + 1.9 + i * 0.2, 0.7, val[i]); cue(A + 1.9 + i * 0.2, 'pop', 0.45); });
      cue(A + 2.6, 'ding', 0.7);
      const r6 = rng(66), amp = wave.map(() => 0.35 + r6() * 0.65), phs = wave.map(() => r6() * 6.28);
      onFrame((t) => {
        if (t < A - 1 || t > A + 4.5) return;
        const on = prog(t, A + 1.35, A + 1.6);
        wave.forEach((e, k) => { e.style.transform = `scaleY(${(0.08 + on * amp[k] * (0.45 + 0.55 * Math.abs(Math.sin(t * 9 + phs[k] + k * 0.4)))).toFixed(3)})`; });
        orb.style.boxShadow = `0 0 ${60 + Math.sin(t * 6) * 26}px rgba(46,230,214,.75), 0 0 150px rgba(46,230,214,.35), inset -14px -20px 40px rgba(0,0,0,.35)`;
        ns.forEach((e, i) => { e.textContent = Math.round(val[i] * 100 * prog(t, A + 1.9 + i * 0.2, A + 2.6 + i * 0.2, 'power3.out')) + '%'; });
      });
    }

    /* ── 7 · hiring pipeline, stage by stage ── */
    {
      const A = T(6);
      const names = ['تقديم', 'فرز', 'مقابلة', 'عرض', 'قرار'], CWK = 150, CP = 165.5;
      const init = [[0, 0], [0, 1], [0, 2], [0, 3], [1, 0], [1, 1], [1, 2], [2, 0], [2, 1], [3, 0]];
      const moves = { 3: [[0, 3], [1, 3], 0.5], 6: [[1, 2], [2, 2], 1.0], 8: [[2, 1], [3, 1], 1.5], 9: [[3, 0], [4, 0], 2.0] };
      const b = mod(6, 'flag', 'مراحل التوظيف', 'من التقديم إلى اتخاذ القرار', `
        <div class="a" style="left:0;right:0;top:0;height:560px">${names.map((n, k) => `<div class="kcol" style="right:${k * CP}px;width:${CWK}px"><b>${n}</b></div>`).join('')}
        ${init.map(() => `<div class="kcard kc7"><div class="avatar"></div><div class="col" style="gap:7px;flex:1">${sk('90%', 't')}${sk('60%')}</div></div>`).join('')}</div>
        <div class="a" style="left:0;right:0;top:600px;height:210px;border-radius:28px;background:rgba(255,255,255,.05);border:1px solid rgba(125,243,232,.2);padding:24px 28px">
          <div class="row" style="justify-content:space-between"><div class="ttl" style="font-size:30px">مسار المرشح</div><span class="chip green-c dn7" style="font-weight:700">${icon('check', 26, '#a8f5cf')}تم اتخاذ القرار</span></div>
          <div class="a" style="left:60px;right:60px;top:128px;height:6px;border-radius:3px;background:rgba(255,255,255,.14)"><div class="pr7" style="position:absolute;right:0;top:0;height:6px;width:100%;border-radius:3px;background:linear-gradient(270deg,#2ee6d6,#f4c95d);transform-origin:100% 50%;box-shadow:0 0 14px rgba(46,230,214,.8)"></div></div>
          ${names.map((n, k) => `<div class="a dt7" style="right:${46 + k * 173}px;top:114px;width:34px;height:34px;border-radius:50%;background:#0c3d43;border:4px solid #2ee6d6"></div>`).join('')}</div>
        <div class="a row" style="left:0;right:0;top:850px;gap:16px"><div class="kpi" style="flex:1"><div class="lbl" style="font-size:25px">في المسار</div><div class="num">10</div></div><div class="kpi" style="flex:1"><div class="lbl" style="font-size:25px">بانتظار إجراء</div><div class="num">3</div></div><div class="kpi" style="flex:1;display:flex;align-items:center;justify-content:center">${tag()}</div></div>`);
      const cards = $$('.kc7', b), pr = $('.pr7', b), dots = $$('.dt7', b);
      const pos = (c, r) => [812 - c * CP - CWK + 6, 78 + r * 108];
      Object.values(moves).forEach((m) => cue(A + m[2], 'swish', 0.7));
      cue(A + 2.42, 'ding', 1);
      pop($('.dn7', b), A + 2.42, 0.45);
      enter(pr, { scaleX: 0 }, { scaleX: 1 }, A + 0.5, 1.9, 'power1.inOut');
      onFrame((t) => {
        if (t < A - 1 || t > A + 4.5) return;
        cards.forEach((e, i) => {
          let [c, r] = init[i], lift = 0;
          const m = moves[i];
          if (m) { const f = prog(t, A + m[2], A + m[2] + 0.42, 'power3.inOut'); c = lerp(m[0][0], m[1][0], f); r = lerp(m[0][1], m[1][1], f); lift = Math.sin(f * Math.PI); }
          const [x, y] = pos(c, r);
          e.style.transform = `translate(${x.toFixed(1)}px,${(y - lift * 34).toFixed(1)}px) scale(${(1 + lift * 0.1).toFixed(3)}) rotate(${(lift * -4).toFixed(2)}deg)`;
          e.style.zIndex = lift > 0.01 ? 5 : 1;
          if (i === 9) e.classList.toggle('win-k', t >= A + 2.42);
        });
        dots.forEach((d, k) => { const on = t >= A + 0.5 + k * 0.475; d.style.background = on ? (k === 4 ? '#f4c95d' : '#2ee6d6') : '#0c3d43'; d.style.borderColor = k === 4 && on ? '#ffe7a8' : '#2ee6d6'; });
      });
    }

    /* ── 8 · candidate communication & procedures ── */
    {
      const A = T(7);
      const b = mod(7, 'chat', 'التواصل مع المرشحين', 'وإدارة إجراءات التوظيف', `
        <div class="a" style="left:0;right:0;top:0;height:300px;border-radius:28px;background:rgba(255,255,255,.05);border:1px solid rgba(125,243,232,.22);padding:24px 28px">
          <div class="row" style="justify-content:space-between"><div class="ttl" style="font-size:32px">دعوة لمقابلة</div><span class="chip">قالب جاهز</span></div>
          <div class="col" style="gap:14px;margin-top:22px">${sk('92%')}${sk('78%')}${sk('54%')}</div>
          <div class="btn a sd8" style="left:28px;bottom:24px;padding:14px 34px;font-size:32px;border-radius:20px">${icon('send', 32, '#04282c')}<span>إرسال للمرشحين</span></div></div>
        ${[0, 1, 2].map((i) => `<div class="lrow" style="top:${326 + i * 116}px"><div class="avatar"></div><div class="col" style="gap:9px;flex:1">${sk((40 + i * 9) + '%', 't', 'height:14px')}${sk((26 + i * 6) + '%', '', 'height:10px')}</div><span class="chip green-c ok8" style="font-weight:700">${icon('check', 24, '#a8f5cf')}تم الإرسال</span></div>`).join('')}
        <div class="a row iv8" style="left:0;right:0;top:690px;height:150px;border-radius:28px;background:linear-gradient(160deg,rgba(150,112,30,.35),rgba(52,37,8,.4));border:1.5px solid rgba(244,201,93,.55);padding:0 26px;gap:20px">
          <div class="ico" style="color:#ffe7a8;background:linear-gradient(145deg,#8a6a22,#3f2f0c);border-color:rgba(244,201,93,.5)">${ic.cal}</div><div class="col" style="flex:1;gap:4px"><div class="ttl" style="font-size:32px">مقابلة مجدولة</div><div class="sub">الأحد · <span class="num" style="font-family:'Plex';font-weight:500">10:00</span> ص</div></div><span class="chip gold-c sc8" style="font-weight:700">تمت الجدولة</span></div>
        ${['إشعار المرشح', 'تحديث حالة الطلب', 'توثيق الإجراء'].map((lb, i) => `<div class="a row" style="left:0;right:0;top:${868 + i * 62}px;gap:16px"><div class="ck8">${chk(42)}</div><div class="ttl" style="font-size:29px;font-weight:600">${lb}</div></div>`).join('')}
        <div class="cursor cur8">${ic.cursor}</div>`);
      const sd = $('.sd8', b), cur = $('.cur8', b);
      enter(cur, { x: 420, y: 520, opacity: 0 }, { x: 240, y: 262, opacity: 1 }, A + 0.1, 0.38, 'power2.inOut');
      tl.to(sd, { scale: 0.93, duration: 0.07 }, A + 0.5).to(sd, { scale: 1, duration: 0.3, ease: 'back.out(2.5)' }, A + 0.57);
      tl.to(cur, { opacity: 0, duration: 0.3 }, A + 0.9);
      cue(A + 0.5, 'click', 1); cue(A + 0.55, 'swish', 0.7);
      $$('.ok8', b).forEach((e, i) => { pop(e, A + 0.72 + i * 0.16, 0.4); cue(A + 0.72 + i * 0.16, 'ding', 0.5); });
      enter($('.iv8', b), { x: -260, opacity: 0 }, { x: 0, opacity: 1 }, A + 1.3, 0.5, 'back.out(1.4)'); cue(A + 1.3, 'swish', 0.7);
      pop($('.sc8', b), A + 1.7, 0.4); cue(A + 1.7, 'pop', 0.6);
      $$('.ck8', b).forEach((e, i) => { pop(e, A + 1.95 + i * 0.2, 0.35); cue(A + 1.95 + i * 0.2, 'pop', 0.5); });
      const note = accent(7, `<div class="bubble me c" style="white-space:nowrap;font-size:30px">${'تم إشعار 3 مرشحين'}</div>`, 30, 236, 110);
      pop(note, A + 1.1, 0.45);
    }

    /* ── 9 · dashboards & analytics ── */
    {
      const A = T(8);
      const pts = [[20, 205], [130, 180], [240, 190], [350, 140], [460, 150], [570, 95], [680, 80], [780, 36]];
      const dpath = 'M' + pts.map((p) => p.join(' ')).join('L');
      const fun = [['متقدمون', 1], ['مفروزون', 0.74], ['مقابلات', 0.46], ['عروض', 0.24]];
      const b = mod(8, 'chart', 'مؤشرات أداء التوظيف', 'تحليلات لحظية', `
        <div class="a row" style="left:0;right:0;top:0;gap:20px">
          <div class="kpi" style="flex:1;height:200px"><div class="lbl" style="font-size:26px">متوسط وقت التوظيف</div><div class="row" style="gap:12px;align-items:baseline"><div class="num k9a" style="font-size:84px"></div><div class="lbl" style="font-size:28px">يوم</div></div></div>
          <div class="kpi" style="flex:1;height:200px"><div class="lbl" style="font-size:26px">معدل التحويل</div><div class="num k9b" style="font-size:84px"></div></div></div>
        <div class="a" style="left:0;right:0;top:226px;height:350px;border-radius:28px;background:rgba(0,0,0,.24);border:1px solid rgba(125,243,232,.2);padding:20px 24px">
          <div class="row" style="justify-content:space-between"><div class="ttl" style="font-size:30px">التعيينات خلال الفترة</div></div>
          <svg viewBox="0 0 800 240" width="764" height="240" style="display:block;margin-top:14px;overflow:visible;direction:ltr">
            <defs><linearGradient id="ar9" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2ee6d6" stop-opacity=".4"/><stop offset="1" stop-color="#2ee6d6" stop-opacity="0"/></linearGradient></defs>
            ${[60, 120, 180, 235].map((y) => `<path d="M0 ${y}H800" stroke="rgba(255,255,255,.09)" stroke-width="2"/>`).join('')}
            <path class="ar9" d="${dpath}L780 238L20 238Z" fill="url(#ar9)"/>
            <path class="ln9" d="${dpath}" fill="none" stroke="#7df3e8" stroke-width="6" stroke-linecap="round" stroke-linejoin="round" style="filter:drop-shadow(0 0 8px #2ee6d6)"/>
            <circle class="dt9" cx="780" cy="36" r="12" fill="#f4c95d" stroke="#fff" stroke-width="4"/></svg></div>
        <div class="a" style="left:0;right:0;top:602px;height:440px;border-radius:28px;background:rgba(0,0,0,.24);border:1px solid rgba(125,243,232,.2);padding:20px 24px">
          <div class="ttl" style="font-size:30px">قمع التوظيف</div>
          ${fun.map(([lb, v], i) => `<div class="a row" style="left:24px;right:24px;top:${84 + i * 84}px;gap:18px"><div class="lbl" style="width:150px;font-size:27px;color:#d8efed">${lb}</div><div style="flex:1;height:54px;position:relative"><div class="fn9" style="position:absolute;right:0;top:0;height:54px;width:${v * 100}%;border-radius:14px;transform-origin:100% 50%;background:linear-gradient(270deg,${i === 3 ? '#f4c95d,#ffe7a8' : '#17b5a8,#7df3e8'});box-shadow:0 0 18px rgba(46,230,214,.35)"></div></div></div>`).join('')}</div>`, tag('بيانات توضيحية'));
      const ka = $('.k9a', b), kb = $('.k9b', b);
      UI.draw($('.ln9', b), A + 0.45, 1.5); enter($('.ar9', b), { opacity: 0 }, { opacity: 1 }, A + 1.2, 0.9, 'power1.out');
      const dt = $('.dt9', b); gsap.set(dt, { transformOrigin: '50% 50%' }); pop(dt, A + 1.9, 0.4);
      $$('.fn9', b).forEach((e, i) => { grow(e, A + 1.2 + i * 0.18, 0.6); cue(A + 1.2 + i * 0.18, 'pop', 0.45); });
      cue(A + 0.45, 'swish', 0.7); cue(A + 1.95, 'ding', 0.9); cue(A + 2.3, 'sparkle', 0.7);
      onFrame((t) => {
        if (t < A - 1 || t > A + 4.5) return;
        ka.textContent = Math.round(lerp(34, 18, prog(t, A + 0.3, A + 1.7, 'power2.out')));
        kb.textContent = Math.round(24 * prog(t, A + 0.4, A + 1.8, 'power2.out')) + '%';
      });
    }

    /* ── HUD: step indicator + headline (always on top, outside the 3D world) ── */
    const heads = ['إنشاء ونشر الوظائف', 'استقبال المتقدمين في نظام موحد', 'رفع السير بالجملة وبناء قاعدة مواهب', 'بحث ذكي وفرز المرشحين', 'تحليل مطابقة المرشح للمتطلبات', 'مقابلات مدعومة بالذكاء الاصطناعي', 'إدارة مراحل التوظيف', 'التواصل مع المرشحين وإدارة الإجراءات', 'مؤشرات وتحليلات لأداء التوظيف'];
    const hud = add(sc.root, `<div class="ehud" style="position:absolute;inset:0"><div style="position:absolute;left:0;right:0;top:0;height:420px;background:linear-gradient(180deg,rgba(3,16,18,.96) 0%,rgba(3,16,18,.86) 58%,rgba(3,16,18,0) 100%)"></div>
      <div style="position:absolute;left:0;right:0;top:44px;text-align:center;font:800 34px/1 'Alexandria';color:var(--teal-soft)"><span style="direction:ltr;unicode-bidi:isolate;display:inline-block"><span class="num hn"></span><span style="color:var(--mute);font-size:26px"> / 9</span></span></div>
      <div style="position:absolute;left:70px;right:70px;top:96px;display:flex;gap:10px">${heads.map(() => '<div class="hudseg"><i></i></div>').join('')}</div></div>`);
    const segs = $$('.hudseg i', hud), hn = $('.hn', hud);
    heads.forEach((h, i) => {
      const e = add(hud, `<div class="c h3 glowtxt" style="left:40px;width:1000px;top:136px;font-size:${h.length > 30 ? 46 : 52}px">${h}</div>`);
      reveal(e, T(i) + 0.1, { stagger: 0.07, dur: 0.5, y: 30 });
      out(e, i === 8 ? 56.9 : T(i) + 2.72, 0.24, { y: -24 });
    });
    for (let i = 1; i < 9; i++) cue(T(i) - 0.34, 'whoosh', 0.55);
    cue(56.85, 'whoosh', 0.9);

    /* ── camera: fly module to module, tilt into each move, pull back to the whole system ── */
    const io = E.ez('power3.inOut');
    const focus = (i) => [ORDER[i][0] * PX + 450, ORDER[i][1] * PY + 620];
    onFrame((t) => {
      if (t < 30 || t >= 58) return;
      let s = 0; for (let k = 1; k < 9; k++) s += io(clamp((t - (T(k) - 0.36)) / 0.72));
      const i = Math.min(7, Math.floor(s)), fr = s - i, a = focus(i), b = focus(i + 1);
      let fx = lerp(a[0], b[0], fr), fy = lerp(a[1], b[1], fr);
      const m = Math.sin(fr * Math.PI), dx = Math.sign(b[0] - a[0]), dy = Math.sign(b[1] - a[1]);
      const local = ((t - T0) % D) / D;
      let z = -480 * m + local * 46 + 95, ry = -dx * 17 * m + Math.sin(t * 0.8) * 2.6, rx = dy * 11 * m + 1.5 + Math.cos(t * 0.6) * 1.2;
      const intro = 1 - prog(t, 30, 30.65, 'expo.out');
      z -= intro * 1500; ry += intro * 24; rx += intro * 10;
      const g = prog(t, 56.9, 57.95, 'power3.inOut');
      if (g > 0) { fx = lerp(fx, PX + 450, g); fy = lerp(fy, PY + 620 - 250, g); z = lerp(z, -3500, g); rx = lerp(rx, 20, g); ry = lerp(ry, -12, g); }
      rig.style.transform = `translateZ(${z.toFixed(1)}px) rotateX(${rx.toFixed(2)}deg) rotateY(${ry.toFixed(2)}deg)`;
      board.style.transform = `translate3d(${(AX - fx).toFixed(1)}px,${(AY - fy).toFixed(1)}px,0)`;
      for (const md of mods) { const near = g > 0 || (Math.abs(md.c * PX + 450 - fx) < 1750 && Math.abs(md.r * PY + 620 - fy) < 2300); md.e.style.display = near ? 'block' : 'none'; }
      const cur = Math.min(8, Math.floor((t - T0) / D));
      hn.textContent = cur + 1;
      segs.forEach((sg, k) => { sg.style.transform = `scaleX(${k < cur ? 1 : k === cur ? clamp((t - T(k)) / D) : 0})`; });
      hud.style.opacity = 1 - prog(t, 57.0, 57.5);
    });
  })();


  /* ══════════ SCENE 5 · ONE JOURNEY, ONE INTERFACE (58 – 72) ══════════ */
  (function S5() {
    const sc = scene('e5', 58, 72.01), w = sc.world;
    sc.root.insertBefore(E.el(`<div class="floor"></div>`), sc.drift);
    gsap.set(sc.cam, { transformOrigin: '540px 900px' });
    enter(sc.cam, { scale: 0.86 }, { scale: 1 }, 58.0, 0.7, 'expo.out');
    tl.to(sc.cam, { scale: 1.04, duration: 6.6, ease: 'sine.inOut' }, 58.8);
    flash(58.0, { color: '160,255,245', a: 0.55, dur: 0.6, y: 800 });
    cue(58.0, 'impact', 0.6);

    const NY = (i) => 300 + i * 160, NT = (i) => 58.5 + i;
    const nodes = [['brief', 'نشر الوظيفة', 'إنشاء الإعلان ونشره'], ['users', 'استقبال المتقدمين', 'كل الطلبات في نظام واحد'], ['filter', 'الفرز والمطابقة', 'تحليل السير وترتيب المرشحين'],
      ['mic', 'المقابلات', 'جدولة ومقابلات ذكية'], ['flag', 'القرار', 'مراحل واضحة حتى اتخاذ القرار'], ['user', 'اختيار المرشح', 'المرشح الأنسب للوظيفة']];

    /* the scattered tools that the journey replaces */
    const mini = (kind) => kind === 'sheet'
      ? `<div class="sheetwin c" style="width:300px;height:230px"><div class="bar" style="height:36px"><i></i><i></i><i></i></div><div class="grid" style="top:36px;background-size:60px 32px"><div class="hdr" style="height:32px"></div></div></div>`
      : UI.win(kind, kind === 'cv' ? 230 : 280, kind === 'cv' ? 290 : 230, 'متابعة');
    const kinds = ['job', 'sheet', 'cv', 'mail', 'sheet', 'mail', 'cv', 'job', 'mail', 'sheet', 'job', 'cv'];
    const rr = rng(58);
    const tools = kinds.map((k, i) => {
      const n = i % 6, e = add(w, mini(k));
      return { e, n, x: (i < 6 ? 120 : 520) + (rr() - 0.5) * 160, y: NY(n) - 50 + (rr() - 0.5) * 60, rot: (rr() - 0.5) * 30, ph: rr() * 6.28, z: -60 - i * 12 };
    });
    tools.forEach((tool, i) => { if (i < 6) cue(NT(tool.n) - 0.4, 'swish', 0.55); });

    /* the line + nodes */
    const rail = add(w, `<div class="c" style="left:897px;top:${NY(0) + 66}px;width:6px;height:800px;border-radius:3px;background:rgba(255,255,255,.12)"><div style="position:absolute;inset:0;border-radius:3px;background:linear-gradient(180deg,#2ee6d6,#7df3e8 70%,#f4c95d);transform-origin:50% 0;box-shadow:0 0 18px rgba(46,230,214,.9)"></div></div>`);
    const railFill = rail.firstElementChild;
    const head = add(w, `<div class="c" style="width:60px;height:60px;border-radius:50%;background:radial-gradient(circle,#fff 0%,#9af7ee 30%,rgba(46,230,214,0) 70%)"></div>`);
    const cards = nodes.map(([icn, title, sub], i) => {
      const gold = i === 5;
      const e = add(w, `<div class="tnode ${gold ? 'gold-n' : ''}"><div class="${gold ? 'avatar gold-a' : 'ico'}" style="${gold ? 'width:84px;height:84px' : ''}">${gold ? '' : ic[icn]}</div>
        <div class="col" style="flex:1;gap:2px"><div class="ttl" style="font-size:36px">${title}</div><div class="sub" style="font-size:25px;${gold ? 'color:#ffe7a8' : ''}">${sub}</div></div><div class="ck">${UI.check(48)}</div></div>`);
      const dot = add(w, `<div class="tdot" style="${gold ? 'border-color:#ffe7a8;background:#f4c95d;box-shadow:0 0 30px rgba(244,201,93,.9)' : ''}"></div>`);
      gsap.set(e, { y: NY(i), z: 20, transformOrigin: '100% 50%' }); gsap.set(dot, { x: 878, y: NY(i) + 44, z: 30 });
      enter(e, { x: 360, opacity: 0, scale: 0.8, rotationY: -40 }, { x: 230, opacity: 1, scale: 1, rotationY: 0 }, NT(i), 0.5, 'back.out(1.5)');
      pop(dot, NT(i) - 0.05, 0.4);
      pop($('.ck', e), NT(i) + 0.45, 0.35);
      cue(NT(i), gold ? 'ding' : 'pop', gold ? 1 : 0.75);
      return e;
    });
    tl.to(cards[5], { scale: 1.07, duration: 0.18, ease: 'power2.out' }, 64.0).to(cards[5], { scale: 1, duration: 0.5, ease: 'power2.out' }, 64.18);
    flash(63.5, { color: '255,225,150', x: 540, y: 1166, r: 900, a: 0.6 });
    cue(63.5, 'sparkle', 1);

    /* manager: relieved, in control */
    const ch = Char.bust({ variant: 'manager', seed: 2.9 }); w.appendChild(ch.el);
    gsap.set(ch.el, { x: 270, y: 1262, scale: 0.9, transformOrigin: '0 0', z: 60 });
    const S = ch.s;
    Object.assign(S, { smile: 0.8, brow: 0.5, lookY: -0.9, lookX: 0.5, turn: 0.25, glow: 0.6 });
    tl.to(S, { lookY: -0.6, lookX: 0.6, smile: 1, duration: 2.5, ease: 'sine.inOut' }, 59.5)
      .to(S, { lookY: -0.2, lookX: 0.5, brow: 0.85, eye: 1.15, smile: 1.2, open: 0.35, duration: 0.4, ease: 'power3.out' }, 63.5)
      .to(S, { lookX: 0, lookY: 0, turn: 0, brow: 0.35, eye: 1, open: 0.3, smile: 1.3, tilt: -2, duration: 0.8, ease: 'sine.inOut' }, 64.4);

    /* key lines (mute-friendly) */
    const k1 = line(w, 'h2 glowtxt', 'التوظيف الذكي..', 120), k2 = line(w, 'h2 glowtxt', 'مو مجرد نظام', 120), k3 = line(w, 'h2 tealtxt', 'طريقة مختلفة لإدارة المواهب', 120, 'font-size:62px');
    reveal(k1, 58.65, { stagger: 0.3 }); out(k1, 60.55, 0.22, { y: -30 });
    reveal(k2, 60.85, { stagger: 0.22 }); out(k2, 62.35, 0.22, { y: -30 });
    reveal(k3, 62.65, { stagger: 0.3 }); out(k3, 65.5, 0.3, { y: -30 });

    /* finale overlay (outside the camera) */
    const fin = add(sc.root, `<div class="ehud" style="position:absolute;inset:0"><div class="dm" style="position:absolute;inset:0;background:radial-gradient(ellipse 80% 60% at 50% 45%,rgba(3,22,25,.9),rgba(2,10,12,.975));opacity:0"></div></div>`);
    tl.to($('.dm', fin), { opacity: 1, duration: 0.55, ease: 'power2.inOut' }, 65.5);
    tl.to(sc.cam, { scale: 0.9, duration: 0.6, ease: 'power2.inOut' }, 65.5);
    tl.to(dust, { gold: 1, duration: 1.5 }, 65.5);
    const f1 = add(fin, `<div class="c" style="left:0;width:1080px;top:662px;text-align:center"><div class="gold" style="font:800 104px/1.3 'Alexandria';white-space:nowrap">مستقبل التوظيف</div></div>`);
    const f2 = add(fin, `<div class="c h1" style="left:0;width:1080px;top:826px;font-size:92px">أقرب مما تتخيل.</div>`);
    const fl = add(fin, `<div class="glowline c" style="left:240px;top:1010px;width:600px;background:linear-gradient(90deg,rgba(244,201,93,0),#f4c95d,rgba(244,201,93,0));box-shadow:0 0 18px rgba(244,201,93,.9)"></div>`);
    gsap.set(f1, { transformOrigin: '50% 50%' });
    enter(f1, { scale: 2.1, opacity: 0 }, { scale: 1, opacity: 1 }, 65.86, 0.2, 'power3.in');
    tl.to(f1, { scale: 1.04, duration: 2.2, ease: 'sine.inOut' }, 66.1);
    reveal(f2, 66.3, { stagger: 0.16 });
    enter(fl, { scaleX: 0, opacity: 0 }, { scaleX: 1, opacity: 1 }, 66.9, 0.7, 'power3.out');
    tl.fromTo(sc.shake, { v: 26 }, { v: 0, duration: 0.6, ease: 'power2.out', immediateRender: false }, 66.05);
    flash(66.05, { color: '255,225,150', y: 760, a: 0.85 });
    cue(64.0, 'riser', 1, { dur: 2.05 }); cue(66.05, 'impact', 1); cue(66.3, 'sparkle', 0.7);
    out([f1, f2, fl], 68.15, 0.3, { scale: 0.94 });
    const soon = add(fin, `<div class="c" style="left:0;width:1080px;top:700px;text-align:center"><div class="gold" style="font:800 230px/1.3 'Alexandria'">قريبا..</div></div>`);
    gsap.set(soon, { transformOrigin: '50% 50%' });
    enter(soon, { scale: 0.5, opacity: 0 }, { scale: 1, opacity: 1 }, 68.42, 0.16, 'power2.in');
    tl.to(soon, { scale: 1.08, duration: 3.4, ease: 'sine.out' }, 68.6);
    const sl = add(fin, `<div class="glowline c" style="left:290px;top:1030px;width:500px"></div>`);
    enter(sl, { scaleX: 0, opacity: 0 }, { scaleX: 1, opacity: 1 }, 68.7, 0.8, 'power3.out');
    flash(68.55, { color: '255,225,150', y: 860, a: 0.9 });
    cue(68.55, 'impact', 1); cue(68.7, 'sparkle', 0.9); cue(68.2, 'whoosh', 0.6);
    particles({ n: 420, seed: 77, t0: 68.55, t1: 71.6, spread: 0.3, swirl: 120, size: 2.6, gold: 0.75, ease: 'power3.out', fadeIn: 0.1, fadeOut: 0.6, alpha: 0.9,
      from: (i, r) => ({ x: 540 + (r() - 0.5) * 500, y: 860 + (r() - 0.5) * 160 }), to: (i, r) => { const a = r() * 6.283, d = 420 + r() * 900; return { x: 540 + Math.cos(a) * d, y: 860 + Math.sin(a) * d * 1.2 }; } });
    tl.to('#fade', { opacity: 1, duration: 1.35, ease: 'power1.in' }, 70.6);

    onFrame((t) => {
      if (t < 58 || t > 72.01) return;
      ch.update(t);
      /* rail progress: reaches node i exactly when it pops */
      const u = clamp(t - 58.5, 0, 5), seg = Math.min(4, Math.floor(u)), yy = (seg + E.ez('power2.inOut')(u - seg)) * 160;
      const on = prog(t, 58.2, 58.5);
      railFill.style.transform = `scaleY(${(yy / 800).toFixed(4)})`;
      head.style.opacity = on * (1 - prog(t, 63.6, 64.2));
      head.style.transform = `translate3d(${870}px,${(NY(0) + 36 + yy).toFixed(1)}px,40px) scale(${(1 + Math.sin(t * 9) * 0.12).toFixed(3)})`;
      for (const k of tools) {
        const a = NT(k.n) - 0.5, f = prog(t, a, a + 0.42, 'power3.in'), inn = back(prog(t, 58.0 + k.n * 0.03, 58.4 + k.n * 0.03));
        const x = lerp(k.x + Math.sin(t * 0.9 + k.ph) * 14, 800, f), y = lerp(k.y + Math.cos(t * 0.8 + k.ph) * 12, NY(k.n) - 40, f);
        k.e.style.opacity = (clamp(inn * 2) * (1 - prog(t, a + 0.25, a + 0.42)) * 0.92).toFixed(3);
        k.e.style.transform = `translate3d(${x.toFixed(1)}px,${y.toFixed(1)}px,${k.z}px) rotateZ(${(k.rot * (1 - f) + f * 40).toFixed(2)}deg) scale(${(inn * (1 - f * 0.85)).toFixed(3)})`;
      }
    });
  })();

  /*__NEXT__*/

  /* ── voice-over placement (word ranges inside vo/employer/<line>.json), captions, music map ── */
  window.VO = [
    { line: 'a1', w: [0, 2], at: 0.5 }, { line: 'a1', w: [3, 5], at: 2.8 }, { line: 'a1', w: [6, 10], at: 5.6 },
    { line: 'b1', w: [0, 2], at: 10.4 }, { line: 'b1', w: [3, 3], at: 12.4 }, { line: 'b1', w: [4, 5], at: 14.2 }, { line: 'b1', w: [6, 11], at: 16.4 },
    { line: 'c1', w: [0, 0], at: 20.8 }, { line: 'c1', w: [1, 9], at: 22.0 },
    { line: 'd1', w: [0, 2], at: 30.3 }, { line: 'd1', w: [3, 8], at: 34.4 }, { line: 'd1', w: [9, 10], at: 45.3 }, { line: 'd1', w: [11, 13], at: 48.3 }, { line: 'd1', w: [14, 20], at: 53.6 },
    { line: 'e1', w: [0, 2], at: 58.6 }, { line: 'e1', w: [3, 5], at: 60.8 }, { line: 'e1', w: [6, 10], at: 62.6 },
  ];
  window.MUSIC = { sections: [{ t: 0, kind: 'tension' }, { t: 10, kind: 'pulse' }, { t: 20, kind: 'reveal' }, { t: 30, kind: 'drive' }, { t: 58, kind: 'finale' }, { t: 70.5, kind: 'end' }], silences: [[19.9, 20.8]] };
  E.start({ duration: 72, audio: '../out/employer-audio.wav', captions: [
    { a: 0.5, b: 2.6, text: 'عندك وظيفة شاغرة..' }, { a: 2.8, b: 5.0, text: 'وجاك مئات المتقدمين..' }, { a: 5.6, b: 8.0, text: 'بس كيف تعرف مين الأنسب؟' },
    { a: 10.4, b: 12.1, text: 'فرز سير ذاتية..' }, { a: 12.4, b: 13.9, text: 'ومقابلات..' }, { a: 14.2, b: 16.2, text: 'ومتابعة متقدمين..' }, { a: 16.4, b: 19.5, text: 'ووقت كبير يضيع على مهام متكررة!' },
    { a: 20.8, b: 21.8, text: 'طيب..' }, { a: 22.0, b: 25.8, text: 'وش لو صارت رحلة التوظيف كلها في نظام واحد؟' },
    { a: 30.3, b: 32.1, text: 'من إعلان الوظيفة..' }, { a: 34.4, b: 37.7, text: 'إلى فرز المتقدمين وتحليل السير الذاتية..' }, { a: 45.3, b: 47.3, text: 'والمقابلات الذكية..' }, { a: 48.3, b: 50.3, text: 'وإدارة كل مرحلة..' },
    { a: 53.6, b: 57.4, text: 'وحتى مؤشرات تقيس لك أداء التوظيف بالكامل!' },
    { a: 58.6, b: 60.6, text: 'لأن التوظيف الذكي..' }, { a: 60.8, b: 62.4, text: 'مو مجرد نظام..' }, { a: 62.6, b: 65.9, text: 'هو طريقة مختلفة لإدارة المواهب.' },
  ] });
})();
