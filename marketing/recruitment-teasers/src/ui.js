/* UI kit: small HTML builders shared by both films. All labels are generic – no brand, no logo, no URL. */
(function () {
  const I = (d, extra = '') => `<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" ${extra}>${d}</svg>`;
  const ic = {
    brief: I('<rect x="3" y="7" width="18" height="13" rx="2.5"/><path d="M9 7V5a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2M3 13h18"/>'),
    search: I('<circle cx="11" cy="11" r="6.5"/><path d="M20 20l-4.2-4.2"/>'),
    doc: I('<path d="M7 3h7l5 5v11a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z"/><path d="M14 3v5h5M9 13h6M9 17h4"/>'),
    bell: I('<path d="M6 16V11a6 6 0 1 1 12 0v5l1.6 2H4.4L6 16z"/><path d="M10 20.5a2.2 2.2 0 0 0 4 0"/>'),
    mark: I('<path d="M7 3h10a1 1 0 0 1 1 1v17l-6-4.2L6 21V4a1 1 0 0 1 1-1z"/>'),
    send: I('<path d="M21 3L10.5 13.5M21 3l-6.5 18-4-7.5L3 9.5 21 3z"/>'),
    spark: I('<path d="M12 3l1.9 5.1L19 10l-5.1 1.9L12 17l-1.9-5.1L5 10l5.1-1.9L12 3z"/><path d="M19 15l.8 2.2L22 18l-2.2.8L19 21l-.8-2.2L16 18l2.2-.8L19 15z"/>'),
    chat: I('<path d="M4 5h16a1 1 0 0 1 1 1v10a1 1 0 0 1-1 1h-8l-5 4v-4H4a1 1 0 0 1-1-1V6a1 1 0 0 1 1-1z"/>'),
    check: I('<path d="M5 12.5l4.5 4.5L19 7.5"/>', 'stroke-width="3"'),
    user: I('<circle cx="12" cy="8" r="4"/><path d="M4 21c0-4.4 3.6-7 8-7s8 2.6 8 7"/>'),
    users: I('<circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c0-3.6 3-6 6.5-6s6.5 2.4 6.5 6"/><circle cx="17.5" cy="9" r="2.6"/><path d="M17 14.2c2.7.2 4.6 2.1 4.6 4.8"/>'),
    chart: I('<path d="M4 20V4M4 20h16"/><path d="M7.5 15.5l3.5-4 3 2.5 4.5-6"/>'),
    cal: I('<rect x="3.5" y="5" width="17" height="15.5" rx="2.5"/><path d="M3.5 10h17M8 3v4M16 3v4"/>'),
    up: I('<path d="M12 16V4M7 8.5L12 4l5 4.5M4 17v2a1.5 1.5 0 0 0 1.5 1.5h13A1.5 1.5 0 0 0 20 19v-2"/>'),
    filter: I('<path d="M3.5 5h17l-6.5 8v6l-4-2v-4L3.5 5z"/>'),
    mic: I('<rect x="9" y="3" width="6" height="11" rx="3"/><path d="M5.5 11.5a6.5 6.5 0 0 0 13 0M12 18v3"/>'),
    flag: I('<path d="M5 21V4M5 4h11l-2 4 2 4H5"/>'),
    clock: I('<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>'),
    mail: I('<rect x="3" y="5.5" width="18" height="13.5" rx="2.5"/><path d="M3.5 7.5L12 13.5l8.5-6"/>'),
    grid: I('<rect x="3.5" y="3.5" width="17" height="17" rx="2"/><path d="M3.5 9.5h17M3.5 15h17M9.5 3.5v17M15 3.5v17"/>'),
    pin: I('<path d="M12 21s-6.5-6-6.5-11a6.5 6.5 0 0 1 13 0c0 5-6.5 11-6.5 11z"/><circle cx="12" cy="10" r="2.3"/>'),
    cursor: `<svg viewBox="0 0 60 60"><path d="M10 4L48 30L30 34L22 52Z" fill="#fff" stroke="#07282c" stroke-width="3.5" stroke-linejoin="round"/></svg>`,
  };

  const C = 2 * Math.PI * 44;
  function ring(color = '#2ee6d6', size = 104) {
    return `<div class="ring" style="width:${size}px;height:${size}px"><svg viewBox="0 0 104 104"><circle cx="52" cy="52" r="44" fill="none" stroke="rgba(255,255,255,.12)" stroke-width="9"/><circle class="arc" cx="52" cy="52" r="44" fill="none" stroke="${color}" stroke-width="9" stroke-linecap="round" stroke-dasharray="${C.toFixed(2)}" stroke-dashoffset="${C.toFixed(2)}" style="filter:drop-shadow(0 0 6px ${color})"/></svg><div class="v" style="font-size:${Math.round(size * 0.29)}px"></div></div>`;
  }
  function setRing(el, p, showPct = true) {
    el.querySelector('.arc').setAttribute('stroke-dashoffset', (C * (1 - Math.max(0, Math.min(1, p)))).toFixed(2));
    el.querySelector('.v').textContent = showPct ? Math.round(p * 100) + '%' : '';
  }

  function jobCard(o) {
    return `<div class="jobcard c" ${o.style ? `style="${o.style}"` : ''}>
      <div class="ico" style="color:${o.gold ? '#ffe7a8' : '#9af7ee'};${o.gold ? 'background:linear-gradient(145deg,#8a6a22,#3f2f0c);border-color:rgba(244,201,93,.5)' : ''}">${ic[o.icon || 'brief']}</div>
      <div class="grow col" style="gap:4px"><div class="ttl">${o.title}</div><div class="sub">${o.sub}</div></div>
      ${o.ring === false ? '' : ring(o.gold ? '#f4c95d' : '#2ee6d6')}
    </div>`;
  }

  /* CV sheet */
  function cv(w = 420, h = 560, extra = '') {
    return `<div class="paper c" style="width:${w}px;height:${h}px;padding:${Math.round(w * 0.075)}px">
      <div class="row" style="gap:${Math.round(w * 0.05)}px"><div class="av" style="width:${Math.round(w * 0.2)}px;height:${Math.round(w * 0.2)}px"></div>
        <div class="col" style="gap:12px;flex:1"><div class="sk t" style="width:70%;height:${Math.round(w * 0.04)}px"></div><div class="sk" style="width:45%"></div></div></div>
      <div class="col" style="gap:${Math.round(h * 0.028)}px;margin-top:${Math.round(h * 0.06)}px">
        <div class="sk t" style="width:34%"></div><div class="sk" style="width:96%"></div><div class="sk" style="width:88%"></div><div class="sk" style="width:62%"></div>
        <div class="sk t" style="width:28%;margin-top:${Math.round(h * 0.02)}px"></div><div class="sk" style="width:92%"></div><div class="sk" style="width:78%"></div>
        <div class="sk t" style="width:38%;margin-top:${Math.round(h * 0.02)}px"></div><div class="sk" style="width:84%"></div><div class="sk" style="width:55%"></div>
      </div>${extra}</div>`;
  }

  /* Mini browser / mail windows used as clutter */
  function win(kind, w, h, label) {
    const body = kind === 'mail'
      ? `<div class="row" style="gap:10px"><div style="width:34px;height:34px;border-radius:50%;background:#c9a24a"></div><div class="col" style="gap:7px;flex:1"><div class="sk" style="width:60%;height:10px"></div><div class="sk" style="width:35%;height:8px"></div></div></div>
         <div class="col" style="gap:9px;margin-top:16px"><div class="sk" style="width:95%;height:9px"></div><div class="sk" style="width:85%;height:9px"></div><div class="sk" style="width:55%;height:9px"></div></div>`
      : kind === 'cv'
        ? `<div class="row" style="gap:12px"><div style="width:46px;height:46px;border-radius:50%;background:#1b7f88"></div><div class="col" style="gap:8px;flex:1"><div class="sk" style="width:70%;height:11px;background:#2aa79c"></div><div class="sk" style="width:45%;height:8px"></div></div></div>
           <div class="col" style="gap:9px;margin-top:16px"><div class="sk" style="width:92%;height:8px"></div><div class="sk" style="width:80%;height:8px"></div><div class="sk" style="width:88%;height:8px"></div><div class="sk" style="width:50%;height:8px"></div></div>`
        : `<div class="sk" style="width:62%;height:15px;background:#1b7f88"></div>
           <div class="col" style="gap:9px;margin-top:14px"><div class="sk" style="width:95%;height:9px"></div><div class="sk" style="width:82%;height:9px"></div><div class="sk" style="width:68%;height:9px"></div></div>
           <div class="wbtn">${label || 'قدّم الآن'}</div>`;
    return `<div class="win c ${kind === 'mail' ? 'mail' : ''}" style="width:${w}px;height:${h}px">${kind === 'cv' ? '' : '<div class="bar"><i></i><i></i><i></i><b></b></div>'}<div class="body">${body}</div></div>`;
  }

  const check = (size = 50) => `<div class="check" style="width:${size}px;height:${size}px;color:#04282c">${ic.check.replace('<svg', `<svg style="width:${size * 0.6}px;height:${size * 0.6}px"`)}</div>`;

  /* Typewriter: reveals `text` between t0 and t1 with a caret. */
  function type(node, text, t0, t1, caret = true) {
    E.onFrame((t) => {
      const n = Math.round(E.prog(t, t0, t1) * text.length);
      const on = caret && t > t0 - 0.3 && t < t1 + 0.9 && (t >= t1 ? Math.floor(t * 2.5) % 2 === 0 : true);
      node.textContent = text.slice(0, n) + (on ? '▏' : '');
    });
  }
  /* Animated integer counter bound to a tweened proxy */
  function counter(node, obj, key = 'v', fmt = (v) => String(Math.round(v))) {
    E.onFrame(() => { node.textContent = fmt(obj[key]); });
  }
  /* SVG path draw-on helper (expects pathLength="1") */
  function draw(path, at, dur = 1, ease = 'power2.inOut') {
    path.setAttribute('pathLength', '1'); path.style.strokeDasharray = '1';
    return E.enter(path, { strokeDashoffset: 1 }, { strokeDashoffset: 0 }, at, dur, ease);
  }

  window.UI = { ic, ring, setRing, jobCard, cv, win, check, type, counter, draw, RC: C };
})();
