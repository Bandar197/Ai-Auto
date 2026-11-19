/* 2.5D Saudi characters built from layered SVG.
 * Each character exposes a plain `s` state object (tweened by GSAP) and `update(t)`
 * which rebuilds the pose: head turn with feature parallax, brows, eyes, blink,
 * mouth, breathing and the screen-glow that lights the face. */
(function () {
  let uid = 0;

  function bust(opt = {}) {
    const v = opt.variant || 'seeker';
    const id = 'ch' + (++uid);
    const manager = v === 'manager';
    const cloth = manager
      ? `<linearGradient id="${id}cl" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset="1" stop-color="#d3dcdd"/></linearGradient>`
      : `<pattern id="${id}pt" width="17" height="17" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><rect width="17" height="17" fill="#fbfbf9"/><rect width="8.5" height="8.5" fill="#c3262d"/><rect x="8.5" y="8.5" width="8.5" height="8.5" fill="#c3262d"/></pattern>`;
    const clothFill = manager ? `url(#${id}cl)` : `url(#${id}pt)`;
    const wrap = document.createElement('div');
    wrap.className = 'c';
    wrap.style.width = '600px'; wrap.style.height = '760px';
    wrap.innerHTML = `
<svg viewBox="0 0 600 760" width="600" height="760" style="overflow:visible;display:block">
 <defs>
  ${cloth}
  <linearGradient id="${id}sk" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#e6b48a"/><stop offset="1" stop-color="#c58d5f"/></linearGradient>
  <linearGradient id="${id}th" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffffff"/><stop offset=".55" stop-color="#e3ebeb"/><stop offset="1" stop-color="#b7c6c8"/></linearGradient>
  <linearGradient id="${id}sh" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#000" stop-opacity=".34"/><stop offset=".3" stop-color="#000" stop-opacity="0"/><stop offset=".7" stop-color="#000" stop-opacity="0"/><stop offset="1" stop-color="#000" stop-opacity=".2"/></linearGradient>
  <radialGradient id="${id}gl" cx="50%" cy="100%" r="80%"><stop offset="0" stop-color="#2ee6d6" stop-opacity=".75"/><stop offset=".6" stop-color="#2ee6d6" stop-opacity=".18"/><stop offset="1" stop-color="#2ee6d6" stop-opacity="0"/></radialGradient>
  <linearGradient id="${id}rm" x1="0" y1="0" x2="1" y2="0"><stop offset=".6" stop-color="#f4c95d" stop-opacity="0"/><stop offset="1" stop-color="#ffe7a8" stop-opacity=".95"/></linearGradient>
  <linearGradient id="${id}vol" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#5a2f14" stop-opacity=".34"/><stop offset=".32" stop-color="#5a2f14" stop-opacity="0"/><stop offset=".78" stop-color="#fff" stop-opacity="0"/><stop offset="1" stop-color="#ffe3b0" stop-opacity=".3"/></linearGradient>
  <clipPath id="${id}fc"><path d="M205 270C205 178 395 178 395 270C395 352 362 432 300 440C238 432 205 352 205 270Z"/></clipPath>
 </defs>
 <g data-k="body">
  <path d="M30 770C30 610 80 548 186 506L252 470L348 470L414 506C520 548 570 610 570 770Z" fill="url(#${id}th)"/>
  <path d="M30 770C30 610 80 548 186 506L252 470L348 470L414 506C520 548 570 610 570 770Z" fill="url(#${id}sh)"/>
  <path d="M30 770C30 610 80 548 186 506L252 470L348 470L414 506C520 548 570 610 570 770Z" fill="url(#${id}gl)" data-k="glowB"/>
  <path d="M300 508V770" stroke="#b9c7c9" stroke-width="3"/>
  <circle cx="300" cy="560" r="6" fill="#c9d4d5"/><circle cx="300" cy="620" r="6" fill="#c9d4d5"/><circle cx="300" cy="680" r="6" fill="#c9d4d5"/>
  <path d="M414 506C520 548 570 610 570 770" fill="none" stroke="url(#${id}rm)" stroke-width="5"/>
 </g>
 <g data-k="head">
  <!-- headwear behind the face -->
  <path d="M300 112C170 112 142 222 156 322C150 410 112 478 74 566L214 520C226 440 222 380 216 300L384 300C378 380 374 440 386 520L526 566C488 478 450 410 444 322C458 222 430 112 300 112Z" fill="${clothFill}"/>
  <path d="M300 112C170 112 142 222 156 322C150 410 112 478 74 566L214 520C226 440 222 380 216 300L384 300C378 380 374 440 386 520L526 566C488 478 450 410 444 322C458 222 430 112 300 112Z" fill="url(#${id}sh)"/>
  <rect x="258" y="396" width="84" height="92" rx="20" fill="#a56d43"/><ellipse cx="300" cy="446" rx="46" ry="16" fill="#3d1f0c" opacity=".35"/>
  <path d="M246 474Q300 520 354 474L350 444Q300 484 250 444Z" fill="#f4f7f7" stroke="#b9c7c9" stroke-width="2"/>
  <path d="M205 270C205 178 395 178 395 270C395 352 362 432 300 440C238 432 205 352 205 270Z" fill="url(#${id}sk)"/>
  <g clip-path="url(#${id}fc)">
   <rect x="200" y="170" width="200" height="280" fill="url(#${id}vol)"/>
   <ellipse cx="300" cy="212" rx="120" ry="42" fill="#5a2f14" opacity=".28"/>
   <ellipse cx="236" cy="352" rx="26" ry="16" fill="#e98f73" opacity=".16"/><ellipse cx="364" cy="352" rx="26" ry="16" fill="#e98f73" opacity=".16"/>
   <rect x="200" y="170" width="200" height="280" fill="url(#${id}gl)" data-k="glowF"/>
   <g data-k="feat">
    <path d="${manager
      ? 'M208 316C210 400 250 452 300 452C350 452 390 400 392 316C384 372 352 398 300 398C248 398 216 372 208 316Z'
      : 'M210 330C214 404 254 448 300 448C346 448 386 404 390 330C382 384 350 408 300 408C250 408 218 384 210 330Z'}" fill="#22150e" opacity="${manager ? 0.95 : 0.88}"/>
    <path d="M266 370Q300 356 334 370Q300 381 266 370Z" fill="#22150e"/>
    <path d="M300 296Q291 344 284 352Q300 364 316 352" fill="none" stroke="#a36b43" stroke-width="3.5" stroke-linecap="round" opacity=".7"/>
    <g data-k="eyeL"><ellipse rx="22" ry="13.5" fill="#fff"/><g data-k="irL"><circle r="10.5" fill="#2b1a10"/><circle r="4.6" fill="#0c0705"/><circle cx="-3.5" cy="-3.5" r="3" fill="#fff"/></g><path d="M-23 -3Q0 -19 23 -3" fill="none" stroke="#22150e" stroke-width="4.5" stroke-linecap="round"/></g>
    <g data-k="eyeR"><ellipse rx="22" ry="13.5" fill="#fff"/><g data-k="irR"><circle r="10.5" fill="#2b1a10"/><circle r="4.6" fill="#0c0705"/><circle cx="-3.5" cy="-3.5" r="3" fill="#fff"/></g><path d="M-23 -3Q0 -19 23 -3" fill="none" stroke="#22150e" stroke-width="4.5" stroke-linecap="round"/></g>
    <rect data-k="browL" x="-27" y="-6" width="54" height="12" rx="6" fill="#1c120c"/>
    <rect data-k="browR" x="-27" y="-6" width="54" height="12" rx="6" fill="#1c120c"/>
    <ellipse data-k="mouthO" cx="300" cy="392" rx="17" ry="0" fill="#3a140f"/>
    <path data-k="mouth" d="M274 390Q300 392 326 390" fill="none" stroke="#6e2f25" stroke-width="5.5" stroke-linecap="round"/>
    ${manager ? `<g data-k="glasses" fill="rgba(180,240,235,.10)" stroke="#111a1b" stroke-width="5"><rect x="226" y="282" width="64" height="48" rx="16"/><rect x="310" y="282" width="64" height="48" rx="16"/><path d="M290 302Q300 296 310 302" fill="none"/><path d="M238 292L262 292" stroke="rgba(255,255,255,.55)" stroke-width="3" stroke-linecap="round"/><path d="M322 292L346 292" stroke="rgba(255,255,255,.55)" stroke-width="3" stroke-linecap="round"/></g>` : ''}
   </g>
  </g>
  <!-- headwear in front: cap over the forehead + side drapes + agal -->
  <path d="M186 268C178 150 238 112 300 112C362 112 422 150 414 268C388 228 344 208 300 216C256 208 212 228 186 268Z" fill="${clothFill}"/>
  <path d="M186 268C178 150 238 112 300 112C362 112 422 150 414 268C388 228 344 208 300 216C256 208 212 228 186 268Z" fill="url(#${id}sh)"/>
  <path d="M300 216L292 150L308 150Z" fill="#000" opacity=".07"/>
  <path d="M200 244C182 330 196 420 150 524L74 566C116 474 146 392 156 310C158 276 176 250 200 244Z" fill="${clothFill}"/>
  <path d="M400 244C418 330 404 420 450 524L526 566C484 474 454 392 444 310C442 276 424 250 400 244Z" fill="${clothFill}"/>
  <path d="M200 244C182 330 196 420 150 524L74 566C116 474 146 392 156 310C158 276 176 250 200 244Z" fill="#000" opacity=".12"/>
  <path d="M444 310C454 392 484 474 526 566" fill="none" stroke="url(#${id}rm)" stroke-width="5"/>
  <path d="M196 176Q300 122 404 176L407 196Q300 142 193 196Z" fill="#0d0f10"/>
  <path d="M190 202Q300 148 410 202L412 221Q300 168 188 221Z" fill="#141718"/>
  <path d="M205 180Q300 132 395 180" fill="none" stroke="#3a4446" stroke-width="2.5" opacity=".8"/>
  <path data-k="sweat" d="M420 250C430 268 434 276 428 284C422 290 412 288 410 280C408 272 414 262 420 250Z" fill="#9fe9ff" opacity="0"/>
 </g>
</svg>`;
    const q = (k) => wrap.querySelector(`[data-k="${k}"]`);
    const n = { body: q('body'), head: q('head'), feat: q('feat'), eyeL: q('eyeL'), eyeR: q('eyeR'), irL: q('irL'), irR: q('irR'), browL: q('browL'), browR: q('browR'),
      mouth: q('mouth'), mouthO: q('mouthO'), glowB: q('glowB'), glowF: q('glowF'), sweat: q('sweat') };
    const s = { brow: 0, furrow: 0, smile: 0, open: 0, eye: 1, lookX: 0, lookY: 0, tilt: 0, turn: 0, bob: 0, glow: 0.5, sweat: 0, flick: 0, seed: opt.seed || 1.7 };

    function blink(t) {              // deterministic natural blink pattern
      const period = 3.1, ph = (t + s.seed) % period;
      const b1 = Math.abs(ph - 0.3) < 0.09 ? 1 - Math.abs(ph - 0.3) / 0.09 : 0;
      const ph2 = (t * 0.83 + s.seed * 2.3) % 5.3;
      const b2 = Math.abs(ph2 - 0.5) < 0.09 ? 1 - Math.abs(ph2 - 0.5) / 0.09 : 0;
      return 1 - Math.max(b1, b2);
    }

    function update(t) {
      const breathe = Math.sin(t * 1.5 + s.seed) * 0.5 + 0.5;
      n.body.setAttribute('transform', `translate(0 ${(breathe * 3).toFixed(2)}) translate(300 760) scale(${(1 + breathe * 0.006).toFixed(4)} ${(1 + breathe * 0.008).toFixed(4)}) translate(-300 -760)`);
      const tilt = s.tilt + Math.sin(t * 0.9 + s.seed) * 0.6;
      const hx = s.turn * 7, hy = s.bob + breathe * 2.2;
      n.head.setAttribute('transform', `translate(${hx.toFixed(2)} ${hy.toFixed(2)}) rotate(${tilt.toFixed(3)} 300 450)`);
      n.feat.setAttribute('transform', `translate(${(s.turn * 15).toFixed(2)} ${(s.lookY * 3).toFixed(2)})`);
      const open = Math.max(0.06, s.eye * blink(t));
      const worried = Math.max(0, -s.brow), raised = Math.max(0, s.brow);
      const ey = 306;
      n.eyeL.setAttribute('transform', `translate(258 ${ey}) scale(1 ${open.toFixed(3)})`);
      n.eyeR.setAttribute('transform', `translate(342 ${ey}) scale(1 ${open.toFixed(3)})`);
      const ix = s.lookX * 8, iy = s.lookY * 4.5;
      n.irL.setAttribute('transform', `translate(${ix.toFixed(2)} ${iy.toFixed(2)})`);
      n.irR.setAttribute('transform', `translate(${ix.toFixed(2)} ${iy.toFixed(2)})`);
      const by = 274 - raised * 13 - worried * 5 + s.furrow * 6;
      const rotL = -15 * worried + 5 * raised + 13 * s.furrow;
      n.browL.setAttribute('transform', `translate(258 ${by.toFixed(2)}) rotate(${rotL.toFixed(2)})`);
      n.browR.setAttribute('transform', `translate(342 ${by.toFixed(2)}) rotate(${(-rotL).toFixed(2)})`);
      const my = 390, cy = my + s.smile * 17 + s.open * 4;
      const ends = my - s.smile * 5;
      n.mouth.setAttribute('d', `M${272 - Math.max(0, s.smile) * 5} ${ends.toFixed(2)}Q300 ${cy.toFixed(2)} ${328 + Math.max(0, s.smile) * 5} ${ends.toFixed(2)}`);
      n.mouthO.setAttribute('ry', (s.open * 11).toFixed(2));
      n.mouthO.setAttribute('rx', (13 + s.open * 5).toFixed(2));
      const g = Math.max(0, s.glow + s.flick * (0.5 + 0.5 * Math.sin(t * 31)) * 0.25);
      n.glowB.setAttribute('opacity', (g * 0.9).toFixed(3));
      n.glowF.setAttribute('opacity', (g * 0.5).toFixed(3));
      n.sweat.setAttribute('opacity', s.sweat.toFixed(3));
      n.sweat.setAttribute('transform', `translate(0 ${(s.sweat * 26).toFixed(2)})`);
    }
    update(0);
    return { el: wrap, s, update };
  }

  /* Laptop seen from behind (lid towards the camera). */
  function laptop() {
    const d = document.createElement('div');
    d.className = 'c'; d.style.width = '560px'; d.style.height = '380px';
    d.innerHTML = `
<svg viewBox="0 0 560 380" width="560" height="380" style="overflow:visible;display:block">
 <defs>
  <linearGradient id="lpA" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#2a3537"/><stop offset="1" stop-color="#0d1213"/></linearGradient>
  <linearGradient id="lpB" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#2ee6d6" stop-opacity="0"/><stop offset=".5" stop-color="#9af7ee"/><stop offset="1" stop-color="#2ee6d6" stop-opacity="0"/></linearGradient>
  <radialGradient id="lpG" cx="50%" cy="0%" r="70%"><stop offset="0" stop-color="#2ee6d6" stop-opacity=".55"/><stop offset="1" stop-color="#2ee6d6" stop-opacity="0"/></radialGradient>
 </defs>
 <ellipse cx="280" cy="30" rx="330" ry="110" fill="url(#lpG)" opacity="0" data-k="halo"/>
 <path d="M52 28H508Q530 28 532 50L552 322H8L28 50Q30 28 52 28Z" fill="url(#lpA)" stroke="rgba(125,243,232,.35)" stroke-width="2"/>
 <path d="M52 29H508" stroke="url(#lpB)" stroke-width="4" stroke-linecap="round"/>
 <rect x="236" y="158" width="88" height="8" rx="4" fill="#2ee6d6" opacity=".7"/>
 <path d="M-22 322H582L566 350Q564 356 556 356H4Q-4 356 -6 350Z" fill="#1a2224" stroke="rgba(125,243,232,.25)" stroke-width="2"/>
 <path d="M-10 356H570" stroke="#000" stroke-opacity=".5" stroke-width="6"/>
</svg>`;
    return { el: d, halo: d.querySelector('[data-k="halo"]') };
  }

  /* Tiny full-body walker used inside the maze (billboard). */
  function walker() {
    const d = document.createElement('div');
    d.className = 'c'; d.style.width = '110px'; d.style.height = '190px';
    d.innerHTML = `
<svg viewBox="0 0 110 190" width="110" height="190" style="overflow:visible;display:block">
 <defs><pattern id="wkp" width="8" height="8" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><rect width="8" height="8" fill="#fbfbf9"/><rect width="4" height="4" fill="#c3262d"/><rect x="4" y="4" width="4" height="4" fill="#c3262d"/></pattern>
 <linearGradient id="wkt" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff"/><stop offset="1" stop-color="#b9c8ca"/></linearGradient></defs>
 <ellipse cx="55" cy="184" rx="36" ry="8" fill="#2ee6d6" opacity=".35"/>
 <g data-k="b">
  <path d="M30 76Q55 62 80 76L90 178Q55 188 20 178Z" fill="url(#wkt)"/>
  <path d="M26 50Q22 86 12 96L34 86Z M84 50Q88 86 98 96L76 86Z" fill="url(#wkp)"/>
  <circle cx="55" cy="46" r="24" fill="#d9a377"/>
  <path d="M28 46C26 18 84 18 82 46C72 32 38 32 28 46Z" fill="url(#wkp)"/>
  <path d="M31 30Q55 16 79 30" stroke="#101314" stroke-width="6" fill="none" stroke-linecap="round"/>
  <circle cx="46" cy="50" r="3.4" fill="#22150e"/><circle cx="64" cy="50" r="3.4" fill="#22150e"/>
  <path d="M42 60Q55 70 68 60Q55 66 42 60Z" fill="#22150e"/>
 </g>
</svg>`;
    return { el: d, body: d.querySelector('[data-k="b"]') };
  }

  /* Full figure seen from behind (final shot): rim-lit silhouette facing the path. */
  function backFigure(variant = 'seeker') {
    const d = document.createElement('div');
    d.className = 'c'; d.style.width = '420px'; d.style.height = '900px';
    const fill = variant === 'manager' ? '#f3f6f6' : 'url(#bfp)';
    d.innerHTML = `
<svg viewBox="0 0 420 900" width="420" height="900" style="overflow:visible;display:block">
 <defs>
  <pattern id="bfp" width="15" height="15" patternUnits="userSpaceOnUse" patternTransform="rotate(45)"><rect width="15" height="15" fill="#f4f2ee"/><rect width="7.5" height="7.5" fill="#b3232a"/><rect x="7.5" y="7.5" width="7.5" height="7.5" fill="#b3232a"/></pattern>
  <linearGradient id="bft" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#eef3f3"/><stop offset="1" stop-color="#7f9799"/></linearGradient>
  <linearGradient id="bfs" x1="0" y1="0" x2="1" y2="0"><stop offset="0" stop-color="#03181b" stop-opacity=".1"/><stop offset=".5" stop-color="#03181b" stop-opacity=".62"/><stop offset="1" stop-color="#03181b" stop-opacity=".1"/></linearGradient>
  <linearGradient id="bfr" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffe7a8"/><stop offset="1" stop-color="#f4c95d" stop-opacity=".1"/></linearGradient>
 </defs>
 <ellipse cx="210" cy="880" rx="190" ry="26" fill="#f4c95d" opacity=".28"/>
 <path d="M96 250C70 268 58 320 56 420L44 868Q210 900 376 868L364 420C362 320 350 268 324 250L262 226H158Z" fill="url(#bft)"/>
 <path d="M96 250C70 268 58 320 56 420L44 868Q210 900 376 868L364 420C362 320 350 268 324 250L262 226H158Z" fill="url(#bfs)"/>
 <path d="M210 40C140 40 122 104 128 168C126 236 104 290 84 352L210 418L336 352C316 290 294 236 292 168C298 104 280 40 210 40Z" fill="${fill}"/>
 <path d="M210 40C140 40 122 104 128 168C126 236 104 290 84 352L210 418L336 352C316 290 294 236 292 168C298 104 280 40 210 40Z" fill="url(#bfs)"/>
 <path d="M134 96Q210 62 286 96L288 116Q210 82 132 116Z" fill="#0c0e0f"/><path d="M130 122Q210 88 290 122L291 140Q210 108 129 140Z" fill="#131617"/>
 <path d="M210 40C140 40 122 104 128 168C126 236 104 290 84 352 M96 250C70 268 58 320 56 420L44 868" fill="none" stroke="url(#bfr)" stroke-width="5" stroke-linecap="round"/>
 <path d="M210 40C280 40 298 104 292 168C294 236 316 290 336 352 M324 250C350 268 362 320 364 420L376 868" fill="none" stroke="url(#bfr)" stroke-width="5" stroke-linecap="round"/>
</svg>`;
    return { el: d };
  }

  window.Char = { bust, laptop, walker, backFigure };
})();
