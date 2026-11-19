#!/usr/bin/env python3
"""Soundtrack builder: procedural score + sound design + voice-over, locked to the picture.

Reads out/<video>.cues.json (exported from the timeline by render/cues.mjs) so every
click, pop, whoosh and impact lands on the exact frame of the motion it belongs to.
The score is synthesised here (120 BPM, D minor → F major lift), so it is original
and royalty-free. Output: out/<video>.wav (48 kHz stereo) + stems in out/tmp/.

Usage: python3 audio/mix.py seeker|employer
"""
import json
import sys
import wave
from pathlib import Path

import numpy as np

SR = 48000
ROOT = Path(__file__).resolve().parent.parent
BEAT = 0.5
BAR = 2.0
rs = np.random.RandomState(7)


# ───────────────────────── helpers ─────────────────────────
def hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def tt(n):
    return np.arange(n) / SR


def fft_filter(x, lo=0.0, hi=24000.0, order=4):
    """Zero-phase Butterworth-shaped band filter in the frequency domain."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    g = np.ones_like(f)
    if hi < SR / 2:
        g *= 1 / np.sqrt(1 + (f / hi) ** (2 * order))
    if lo > 0:
        g *= 1 / np.sqrt(1 + (lo / np.maximum(f, 1e-6)) ** (2 * order))
    return np.fft.irfft(X * g, len(x))


def env_adsr(n, a, d, s, r):
    e = np.ones(n) * s
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    na, nd, nr = min(na, n), min(nd, max(0, n - na)), min(nr, n)
    if na:
        e[:na] = np.linspace(0, 1, na)
    if nd:
        e[na:na + nd] = np.linspace(1, s, nd)
    if nr:
        e[-nr:] *= np.linspace(1, 0, nr)
    return e


def saw(f, n, cutoff, ph=0.0, odd=False, maxh=40):
    """Band-limited saw (or square-ish when odd) with a 12 dB/oct low-pass that may vary in time."""
    t = tt(n)
    out = np.zeros(n)
    cmax = float(np.max(cutoff))
    k = 1
    while k <= maxh and k * f < 16000 and k * f < cmax * 6:
        g = (1.0 / k) / np.sqrt(1 + (k * f / cutoff) ** 4)
        out += g * np.sin(2 * np.pi * k * f * t + ph * k)
        k += 2 if odd else 1
    return out


class Bus:
    def __init__(self, dur):
        self.n = int(dur * SR) + SR * 4
        self.b = np.zeros((2, self.n))

    def add(self, t, x, gain=1.0, pan=0.0):
        i = int(round(t * SR))
        if i < 0:
            x = x[..., -i:]
            i = 0
        if x.ndim == 1:
            l, r = np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)
            x = np.stack([x * l, x * r]) * 1.4142
        m = min(x.shape[1], self.n - i)
        if m > 0:
            self.b[:, i:i + m] += x[:, :m] * gain


def make_ir(seconds, decay, lo=250, hi=7000, seed=1):
    r = np.random.RandomState(seed)
    n = int(seconds * SR)
    ir = np.stack([r.randn(n), r.randn(n)]) * np.exp(-tt(n) / decay)
    ir[:, :int(0.012 * SR)] *= np.linspace(0, 1, int(0.012 * SR))
    ir = np.stack([fft_filter(ir[0], lo, hi, 2), fft_filter(ir[1], lo, hi, 2)])
    return ir / np.sqrt((ir ** 2).sum(axis=1, keepdims=True))


def reverb(x, ir, wet=0.3):
    n = x.shape[1] + ir.shape[1] - 1
    size = 1 << (n - 1).bit_length()
    out = np.stack([np.fft.irfft(np.fft.rfft(x[c], size) * np.fft.rfft(ir[c], size), size)[:x.shape[1]] for c in range(2)])
    return x + out * wet


def smooth(x, sec):
    k = max(1, int(sec * SR))
    c = np.cumsum(np.concatenate([[0.0], x]))
    return (c[k:] - c[:-k]) / k if len(x) > k else x


def follower(x, attack=0.02, release=0.25):
    """Cheap envelope: block max → smoothing."""
    a = np.abs(x)
    blk = 480
    m = a[: len(a) // blk * blk].reshape(-1, blk).max(axis=1)
    out = np.zeros_like(m)
    cur = 0.0
    ka, kr = np.exp(-blk / SR / attack), np.exp(-blk / SR / release)
    for i, v in enumerate(m):
        cur = v + (cur - v) * (ka if v > cur else kr)
        out[i] = cur
    return np.interp(np.arange(len(a)), np.arange(len(m)) * blk + blk / 2, out)


# ───────────────────────── drums ─────────────────────────
def kick(gain=1.0, long=False):
    n = int((0.5 if long else 0.32) * SR)
    t = tt(n)
    f = 46 + 110 * np.exp(-t * 34)
    x = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * (7 if long else 11))
    x += 0.35 * fft_filter(rs.randn(n), 1500, 6000, 2) * np.exp(-t * 220)
    return np.tanh(x * 1.6) * gain


def clap():
    n = int(0.28 * SR)
    t = tt(n)
    x = fft_filter(rs.randn(n), 900, 4200, 2)
    e = sum(np.exp(-np.maximum(0, t - d) * 60) * (t >= d) for d in (0, 0.011, 0.023)) * 0.5 + np.exp(-t * 16) * 0.5
    return x * e


def hat(dec=70, hp=7000):
    n = int(0.12 * SR)
    return fft_filter(rs.randn(n), hp, 15000, 2) * np.exp(-tt(n) * dec)


# ───────────────────────── tonal voices ─────────────────────────
def bass_note(m, dur, bright=1.0):
    n = int(dur * SR)
    t = tt(n)
    cut = 160 + 900 * bright * np.exp(-t * 16)
    x = saw(hz(m), n, cut, maxh=24) + 0.9 * np.sin(2 * np.pi * hz(m) * t)
    return x * env_adsr(n, 0.004, 0.08, 0.75, 0.04)


def pluck(m, dur=0.32, bright=1.0):
    n = int(dur * SR)
    t = tt(n)
    cut = 500 + 5200 * bright * np.exp(-t * 20)
    return saw(hz(m), n, cut, odd=True, maxh=30) * np.exp(-t * 11) * env_adsr(n, 0.002, 0.01, 1, 0.03)


def pad_chord(notes, dur, cutoff=1400, attack=0.5, release=0.9, swell=None):
    n = int((dur + release) * SR)
    L = np.zeros(n)
    R = np.zeros(n)
    t = tt(n)
    cut = cutoff * (1 + 0.25 * np.sin(2 * np.pi * 0.21 * t)) if swell is None else swell(t)
    for i, m in enumerate(notes):
        f = hz(m)
        L += saw(f * 2 ** (-6 / 1200), n, cut, ph=i * 1.3, maxh=18) + 0.5 * saw(f * 2 ** (9 / 1200), n, cut, ph=i * 2.1, maxh=18)
        R += saw(f * 2 ** (6 / 1200), n, cut, ph=i * 0.7, maxh=18) + 0.5 * saw(f * 2 ** (-9 / 1200), n, cut, ph=i * 2.9, maxh=18)
    e = env_adsr(n, attack, 0.2, 0.9, release)
    return np.stack([L, R]) * e / max(1, len(notes)) ** 0.7


def lead(m, dur):
    n = int(dur * SR)
    t = tt(n)
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.2 * t) * np.minimum(1, t / 0.18)
    ph = 2 * np.pi * np.cumsum(hz(m) * vib) / SR
    x = np.sin(ph) + 0.28 * np.sin(2 * ph) + 0.12 * np.sin(3 * ph)
    return x * env_adsr(n, 0.012, 0.1, 0.7, 0.12)


CH = {  # chord tones (MIDI), root for the bass
    'Dm': (38, [50, 57, 62, 65]), 'Bb': (34, [46, 53, 58, 62]), 'F': (41, [53, 57, 60, 65]), 'C': (36, [48, 55, 60, 64]),
    'A': (33, [45, 52, 57, 62]), 'Bbmaj9': (34, [46, 53, 57, 60, 65]), 'Dm9': (38, [50, 57, 60, 64, 65]),
}
MELODY = {  # 8th-note motifs for the drive section
    'Dm': [69, 0, 74, 0, 72, 69, 0, 0], 'Bb': [65, 0, 70, 0, 69, 65, 0, 0], 'F': [69, 0, 72, 0, 77, 0, 76, 72], 'C': [67, 0, 72, 0, 76, 0, 74, 0],
}


def build_music(dur, meta, sfx):
    sections = meta['sections']
    kinds = [(s['t'], sections[i + 1]['t'] if i + 1 < len(sections) else dur, s['kind']) for i, s in enumerate(sections)]
    impacts = sorted(c['t'] for c in sfx if c['type'] == 'impact' and c.get('g', 1) >= 0.9)   # only the big hits steer the harmony
    drums, bassb, padb, arpb, leadb = (Bus(dur) for _ in range(5))
    K, KL, CL, HT, HO = kick(), kick(long=True), clap(), hat(), hat(28, 5500)

    def chord_at(kind, a, b, t):
        bar = int(round((t - a) / BAR))
        nb = int(round((b - a) / BAR))
        if kind == 'tension':
            return 'Dm'
        if kind == 'pulse':
            seq = ['Dm', 'Dm', 'Bb', 'Bb']
            return 'A' if bar == nb - 1 else seq[bar % 4]
        if kind == 'reveal':
            hit = [x for x in impacts if a + 1 < x < b]
            if hit and t >= hit[-1] - 0.01:
                return 'F'
            return ['Bb', 'F', 'C', 'Dm', 'Bb', 'C'][bar % 6]
        if kind == 'drive':
            return 'C' if bar == nb - 1 and nb % 4 == 1 else ['Dm', 'Bb', 'F', 'C'][bar % 4]
        return 'Bb'

    for a, b, kind in kinds:
        if kind == 'end':
            continue
        nb = int(round((b - a) / BAR))
        if kind == 'finale':
            # big held chords that change exactly on the picture's impacts
            hits = [x for x in impacts if a < x < b]
            pts = [a] + hits + [b + 1.5]
            names = ['Bb', 'F', 'Bbmaj9', 'Bbmaj9'] if len(hits) >= 2 else ['Bb', 'Bbmaj9', 'Bbmaj9']
            for i in range(len(pts) - 1):
                root, notes = CH[names[min(i, len(names) - 1)]]
                d = pts[i + 1] - pts[i]
                last = i == len(pts) - 2
                padb.add(pts[i], pad_chord(notes + [notes[0] + 24, notes[1] + 12], d, cutoff=2600 if i else 1500, attack=0.05 if i else 0.8, release=3.5 if last else 0.8), 1.25)
                bassb.add(pts[i], bass_note(root, min(d, 3.5), 0.6) * np.exp(-tt(int(min(d, 3.5) * SR)) * 0.5), 1.1)
                if i:
                    drums.add(pts[i], KL, 1.2)
                # slow arpeggio shimmering over the chord
                steps = int(d / 0.25)
                for s in range(steps):
                    if last and s > 14:
                        break
                    m = notes[s % len(notes)] + 12 * (1 + (s // len(notes)) % 2)
                    arpb.add(pts[i] + s * 0.25, pluck(m, 0.5, 0.8), 0.55 * (0.6 + 0.4 * ((s % 4) == 0)) * (np.exp(-s / 9) if last else 1), pan=0.5 * np.sin(s))
            # soft half-time pulse before the first impact
            t = a
            while t < (hits[0] if hits else b) - 0.01:
                drums.add(t, KL, 0.7)
                drums.add(t + 1.0, CL, 0.25)
                t += BAR
            continue
        for bar in range(nb):
            t0 = a + bar * BAR
            name = chord_at(kind, a, b, t0)
            root, notes = CH[name]
            prog = bar / max(1, nb - 1)
            if kind == 'tension':
                padb.add(t0, pad_chord([38, 45, 50, 57], BAR, cutoff=420 + 500 * prog, attack=0.9, release=1.2), 0.9)
                bassb.add(t0, bass_note(26, BAR, 0.15) * (0.8 + 0.2 * np.sin(2 * np.pi * 3 * tt(int(BAR * SR)))), 0.9)
                drums.add(t0, KL, 0.55)
                drums.add(t0 + 0.28, KL, 0.32)                 # heartbeat: lub-dub
                for s in range(4):
                    drums.add(t0 + s * 0.5 + 0.25, HT, 0.12 + 0.1 * prog, pan=0.4 if s % 2 else -0.4)
            elif kind == 'pulse':
                padb.add(t0, pad_chord(notes, BAR, cutoff=700 + 1300 * prog, attack=0.3), 0.85)
                for s in range(8):
                    bassb.add(t0 + s * 0.25, bass_note(root + (12 if s % 4 == 3 else 0), 0.24, 0.5 + 0.7 * prog), 0.95)
                for s in range(4):
                    drums.add(t0 + s * 0.5, K, 0.75 + 0.2 * prog)
                for s in range(16):
                    drums.add(t0 + s * 0.125, HT, (0.1 + 0.28 * prog) * (1.0 if s % 4 == 2 else 0.55), pan=0.5 if s % 2 else -0.5)
                if bar >= nb - 2:
                    for s in range(8 if bar == nb - 2 else 16):   # snare-ish build
                        step = 0.25 if bar == nb - 2 else 0.125
                        drums.add(t0 + s * step, CL, 0.2 + 0.5 * (s / 16 if bar == nb - 1 else 0.2))
            elif kind == 'reveal':
                sub = 2 if (name == 'C' and bar == 5) else 1
                padb.add(t0, pad_chord(notes + [notes[1] + 12], BAR, cutoff=1500 + 1500 * prog, attack=0.25), 1.0)
                bassb.add(t0, bass_note(root, BAR * 0.98, 0.35) * np.exp(-tt(int(BAR * 0.98 * SR)) * 0.6), 1.0)
                for s in range(16):
                    seq = [0, 1, 2, 3, 2, 1, 2, 3]
                    m = notes[seq[s % 8] % len(notes)] + 12 + (12 if (s // 8) % 2 else 0)
                    arpb.add(t0 + s * 0.125, pluck(m, 0.3, 0.5 + 0.6 * prog), 0.5 * (1.0 if s % 4 == 0 else 0.65), pan=0.6 * np.sin(s * 0.9))
                if bar >= 2:
                    for s in range(4):
                        drums.add(t0 + s * 0.5, K, 0.5 + 0.3 * prog)
                    for s in range(4):
                        drums.add(t0 + s * 0.5 + 0.25, HO, 0.14 + 0.1 * prog)
                if bar == nb - 2 and not [x for x in impacts if a + 1 < x < b and x < t0]:
                    for s in range(8):
                        drums.add(t0 + 1.0 + s * 0.125, CL, 0.15 + 0.06 * s)
            elif kind == 'drive':
                loop = bar // 4
                fill = bar == nb - 1
                padb.add(t0, pad_chord(notes, BAR, cutoff=1700 + 400 * loop, attack=0.08), 0.8)
                pat = [0, 0, 12, 0, 0, 12, 0, 7]
                for s in range(8):
                    bassb.add(t0 + s * 0.25, bass_note(root + pat[s], 0.23, 1.0), 1.0)
                for s in range(4):
                    drums.add(t0 + s * 0.5, K, 1.0)
                    drums.add(t0 + s * 0.5 + 0.25, HO, 0.3, pan=0.3)
                for s in range(16):
                    if s % 2:
                        drums.add(t0 + s * 0.125, HT, 0.14, pan=-0.4 if s % 4 == 1 else 0.4)
                drums.add(t0 + 0.5, CL, 0.6)
                drums.add(t0 + 1.5, CL, 0.6)
                for s in range(16):
                    seq = [0, 2, 1, 3, 2, 1, 3, 2]
                    m = notes[seq[s % 8] % len(notes)] + 12 + (12 if s % 8 >= 4 else 0)
                    arpb.add(t0 + s * 0.125, pluck(m, 0.26, 0.9), 0.36 * (1.0 if s % 4 == 0 else 0.6), pan=0.7 * np.sin(s * 1.3 + bar))
                if loop >= 1 and name in MELODY and not fill:
                    for s, m in enumerate(MELODY[name]):
                        if m:
                            x = lead(m + (12 if loop >= 2 and s % 2 == 0 else 0), 0.42)
                            leadb.add(t0 + s * 0.25, x, 0.42)
                            leadb.add(t0 + s * 0.25 + 0.375, x, 0.14, pan=0.6)   # dotted-8th echo
                if fill:
                    for s in range(16):
                        drums.add(t0 + s * 0.125, CL, 0.12 + 0.045 * s)
                    for s in range(6):
                        drums.add(t0 + 1.25 + s * 0.125, K, 0.5 + 0.08 * s)

    # sidechain "pump" from the kick, glue, space
    kenv = follower(drums.b.sum(axis=0) * 0.5, 0.004, 0.16)
    duck = 1 - 0.42 * np.clip(kenv / (kenv.max() + 1e-9) * 1.6, 0, 1)
    ir = make_ir(3.2, 0.75, seed=3)
    padw = reverb(padb.b * duck, ir, 0.5)
    arpw = reverb(arpb.b, ir, 0.55)
    leadw = reverb(leadb.b, ir, 0.5)
    drumw = reverb(drums.b, make_ir(0.9, 0.16, 400, 9000, seed=5), 0.12)
    bassw = np.stack([fft_filter(bassb.b[0] * duck, 28, 5000, 2)] * 2)
    music = padw * 0.34 + arpw * 0.33 + leadw * 0.5 + drumw * 0.62 + bassw * 0.4
    music = np.stack([fft_filter(music[0], 0, 13000, 2), fft_filter(music[1], 0, 13000, 2)])
    # hard musical silences (time-freeze moments): fast cut, smooth return
    g = np.ones(music.shape[1])
    for a, b in meta.get('silences', []):
        i0, i1 = int(a * SR), int(b * SR)
        g[i0:i1] = 0
        f = int(0.06 * SR)
        g[i0 - f:i0] = np.minimum(g[i0 - f:i0], np.linspace(1, 0, f))
        f2 = int(0.5 * SR)
        g[i1:i1 + f2] = np.minimum(g[i1:i1 + f2], np.linspace(0, 1, f2) ** 2)
    # section dynamics: start restrained, open up for the product, peak at the finale
    level = {'tension': 0.6, 'pulse': 0.8, 'reveal': 0.88, 'drive': 1.0, 'finale': 1.08, 'end': 1.0}
    lv = np.ones(music.shape[1])
    for a, b, kind in kinds:
        lv[int(a * SR):int(b * SR)] = level.get(kind, 1.0)
    sm = smooth(lv, 0.5)
    pad = len(lv) - len(sm)
    g *= np.concatenate([np.full(pad // 2, lv[0]), sm, np.full(pad - pad // 2, lv[-1])])
    end = [s['t'] for s in sections if s['kind'] == 'end']
    if end:
        i0 = int((end[0] - 0.5) * SR)
        f = int(2.0 * SR)
        g[i0:i0 + f] *= np.linspace(1, 0, f) ** 1.5
        g[i0 + f:] = 0
    return music * g


# ───────────────────────── sound design ─────────────────────────
def sweep_noise(dur, f0, f1, q=0.5, seed=0):
    """Noise whose band centre glides f0→f1 (cross-faded bank of band-passed layers)."""
    r = np.random.RandomState(seed)
    n = int(dur * SR)
    src = r.randn(n)
    bands = 8
    out = np.zeros(n)
    pos = np.linspace(0, bands - 1, n)
    for i in range(bands):
        fc = f0 * (f1 / f0) ** (i / (bands - 1))
        layer = fft_filter(src, fc * (1 - q / 2), fc * (1 + q / 2), 2)
        out += layer * np.clip(1 - np.abs(pos - i), 0, 1)
    return out


def sfx_make(kind, c):
    g = c.get('g', 1)
    if kind == 'click':
        n = int(0.05 * SR); t = tt(n)
        x = np.sin(2 * np.pi * 2100 * t) * np.exp(-t * 190) + 0.6 * fft_filter(rs.randn(n), 2500, 9000, 2) * np.exp(-t * 420) + 0.5 * np.sin(2 * np.pi * 240 * t) * np.exp(-t * 90)
        return x * 0.55, 0.0, 0.1
    if kind == 'type':
        n = int(0.035 * SR); t = tt(n)
        return fft_filter(rs.randn(n), 1800, 6000, 2) * np.exp(-t * 260) * 0.55 + np.sin(2 * np.pi * (700 + rs.rand() * 200) * t) * np.exp(-t * 200) * 0.2, rs.rand() * 0.4 - 0.2, 0.05
    if kind == 'tick':
        n = int(0.06 * SR); t = tt(n)
        return (np.sin(2 * np.pi * 2600 * t) * np.exp(-t * 300) + 0.7 * np.sin(2 * np.pi * 1150 * t) * np.exp(-t * 140)) * 0.5, 0.0, 0.15
    if kind == 'pop':
        n = int(0.14 * SR); t = tt(n)
        f = 380 + 520 * (1 - np.exp(-t * 60))
        return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 34) * 0.6, 0.0, 0.2
    if kind == 'ding':
        n = int(0.9 * SR); t = tt(n)
        x = sum(a * np.sin(2 * np.pi * f * t) * np.exp(-t * d) for f, a, d in ((1318.5, 1, 6), (1976, 0.5, 8), (2637, 0.3, 11), (3951, 0.12, 15)))
        return x * 0.34 * env_adsr(n, 0.002, 0.01, 1, 0.05), 0.0, 0.45
    if kind == 'bell':
        n = int(1.2 * SR); t = tt(n)
        x = np.zeros(n)
        for k, f in enumerate((1760, 2217, 1760, 2217)):
            i = int(k * 0.11 * SR); tk = t[: n - i]
            x[i:] += (np.sin(2 * np.pi * f * tk) + 0.4 * np.sin(2 * np.pi * f * 2.76 * tk)) * np.exp(-tk * 9)
        return x * 0.26, 0.0, 0.4
    if kind == 'swish':
        d = 0.3; n = int(d * SR)
        return sweep_noise(d, 1800, 6500, 0.7, seed=int(c['t'] * 100) % 97) * np.sin(np.pi * tt(n) / d) ** 2 * 0.5, (-0.5, 0.5), 0.15
    if kind == 'whoosh':
        d = 0.85; n = int(d * SR); t = tt(n)
        e = np.exp(-((t - 0.5) / 0.19) ** 2)
        x = sweep_noise(d, 300, 4200, 0.9, seed=int(c['t'] * 10) % 89) * e + 0.5 * sweep_noise(d, 90, 500, 1.0, seed=3) * e
        return x * 0.95, (-0.8, 0.8), 0.3, -0.5          # peak lands on the cue
    if kind == 'riser':
        d = c.get('dur', 2.0); n = int(d * SR); t = tt(n)
        e = (t / d) ** 2.2
        f = 220 * (2 ** (t / d * 2.2))
        x = sweep_noise(d, 500, 9000, 0.8, seed=11) * e * 0.8 + 0.35 * np.sin(2 * np.pi * np.cumsum(f) / SR) * e
        x[-int(0.01 * SR):] *= np.linspace(1, 0, int(0.01 * SR))
        return x * 0.6, 0.0, 0.35
    if kind == 'scan':
        d = c.get('dur', 1.5); n = int(d * SR); t = tt(n)
        f = 700 + 900 * (0.5 - 0.5 * np.cos(2 * np.pi * t / d * (2 if d > 1.2 else 1)))
        x = np.sin(2 * np.pi * np.cumsum(f) / SR) * (0.6 + 0.4 * np.sin(2 * np.pi * 26 * t)) * np.sin(np.pi * t / d) ** 0.5
        return x * 0.13, 0.0, 0.3
    if kind == 'sparkle':
        d = 1.1; n = int(d * SR); x = np.zeros(n)
        r = np.random.RandomState(int(c['t'] * 10))
        for _ in range(26):
            i = int(r.rand() ** 1.6 * (n - 4000)); m = 3600; tk = tt(m)
            x[i:i + m] += np.sin(2 * np.pi * (3000 + r.rand() * 6000) * tk) * np.exp(-tk * 55) * (0.3 + 0.7 * r.rand())
        return x * 0.16, 0.0, 0.6
    if kind in ('impact', 'hit'):
        d = 2.4; n = int(d * SR); t = tt(n)
        f = 34 + 70 * np.exp(-t * 9)
        sub = np.tanh(np.sin(2 * np.pi * np.cumsum(f) / SR) * 2.2) * np.exp(-t * (2.0 if kind == 'impact' else 3.0))
        crash = fft_filter(rs.randn(n), 180, 5200 if kind == 'impact' else 2400, 2) * np.exp(-t * 3.2)
        thump = fft_filter(rs.randn(n), 60, 900, 2) * np.exp(-t * 28) * 1.5
        return (sub * 0.95 + crash * 0.4 + thump) * 0.95, 0.0, 0.5
    if kind == 'freeze':
        d = 0.55; n = int(d * SR); t = tt(n)
        f = 900 * 2 ** (-t / d * 3.2)                        # tape-stop: everything winds down…
        x = (np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.5 + sweep_noise(d, 5000, 200, 0.9, seed=2) * 0.7) * (1 - (t / d) ** 3)
        thud = np.sin(2 * np.pi * 52 * tt(int(0.5 * SR))) * np.exp(-tt(int(0.5 * SR)) * 9)       # …and stops dead
        out = np.zeros(n + len(thud)); out[:n] = x; out[n:] += thud * 1.1
        return out * 0.75, 0.0, 0.25
    return None


def build_sfx(dur, cues):
    dry, wet = Bus(dur), Bus(dur)
    for c in cues:
        r = sfx_make(c['type'], c)
        if r is None:
            print('  (no sound for cue type', c['type'], ')')
            continue
        x, pan, send = r[0], r[1], r[2]
        off = r[3] if len(r) > 3 else 0.0
        g = c.get('g', 1)
        if isinstance(pan, tuple):                       # pan sweep
            p = np.linspace(pan[0], pan[1], len(x)) * (1 if int(c['t'] * 7) % 2 else -1)
            x = np.stack([x * np.cos((p + 1) * np.pi / 4), x * np.sin((p + 1) * np.pi / 4)]) * 1.4142
        dry.add(c['t'] + off, x, g)
        wet.add(c['t'] + off, x, g * send)
    return dry.b + (reverb(wet.b, make_ir(2.6, 0.55, seed=9), 1.0) - wet.b)


# ───────────────────────── voice-over ─────────────────────────
def read_wav(p):
    with wave.open(str(p)) as w:
        assert w.getframerate() == SR, f'{p}: expected {SR} Hz'
        x = np.frombuffer(w.readframes(w.getnframes()), dtype=np.int16).astype(np.float64) / 32768
        if w.getnchannels() == 2:
            x = x.reshape(-1, 2).mean(axis=1)
    return x


def build_vo(dur, video, placements):
    bus = Bus(dur)
    cache = {}
    for p in placements:
        d = ROOT / 'vo' / video
        if p['line'] not in cache:
            cache[p['line']] = (read_wav(d / f"{p['line']}.wav"), json.loads((d / f"{p['line']}.json").read_text())['words'])
        x, words = cache[p['line']]
        a, b = p['w']
        t0 = max(0, words[a]['t'] - 0.05)
        nxt = words[b + 1]['t'] if b + 1 < len(words) else len(x) / SR
        t1 = min(words[b]['t'] + words[b]['d'] + 0.22, nxt - 0.02, len(x) / SR)
        seg = x[int(t0 * SR):int(t1 * SR)].copy()
        fi, fo = int(0.012 * SR), int(0.07 * SR)
        seg[:fi] *= np.linspace(0, 1, fi)
        seg[-fo:] *= np.linspace(1, 0, fo)
        bus.add(p['at'] - 0.05, seg)
    v = bus.b[0] / 1.4142
    v = fft_filter(v, 85, 13500, 2)
    # gentle compression + presence
    e = follower(v, 0.005, 0.12)
    v = v / (1 + 2.2 * np.maximum(0, e - 0.12))
    v = v + 0.22 * fft_filter(v, 2500, 7000, 1)
    v = v / (np.abs(v).max() + 1e-9) * 0.8
    st = np.stack([v, v])
    return reverb(st, make_ir(0.7, 0.12, 300, 8000, seed=21), 0.07)


def write_wav(p, x):
    x = np.clip(x, -1, 1)
    with wave.open(str(p), 'wb') as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x.T * 32767).astype(np.int16).tobytes())


def rms_db(x):
    return 20 * np.log10(np.sqrt((x ** 2).mean()) + 1e-9)


def main():
    video = sys.argv[1] if len(sys.argv) > 1 else 'seeker'
    meta = json.loads((ROOT / 'out' / f'{video}.cues.json').read_text())
    dur = meta['duration']
    n = int(dur * SR)
    print('music…'); music = build_music(dur, meta['music'], meta['sfx'])[:, :n]
    print('sfx…'); sfx = build_sfx(dur, meta['sfx'])[:, :n]
    print('voice…'); vo = build_vo(dur, video, meta['vo'])[:, :n]
    # voice always wins: duck the score under speech
    ve = follower(vo[0], 0.03, 0.35)
    duck = 1 - 0.5 * np.clip(ve / 0.12, 0, 1)
    music = music / (np.abs(music).max() + 1e-9) * 0.62
    sfx = sfx / (np.abs(sfx).max() + 1e-9) * 0.8
    mix = vo * 1.0 + music * duck + sfx * 0.85
    mix = np.tanh(mix * 1.15) / np.tanh(1.15)            # soft limiter
    mix = mix / np.abs(mix).max() * 0.94
    fo = int(0.3 * SR); mix[:, -fo:] *= np.linspace(1, 0, fo)
    (ROOT / 'out' / 'tmp').mkdir(parents=True, exist_ok=True)
    write_wav(ROOT / 'out' / f'{video}.wav', mix)
    for name, stem in (('music', music), ('sfx', sfx), ('vo', vo)):
        write_wav(ROOT / 'out' / 'tmp' / f'{video}-{name}.wav', stem / (np.abs(stem).max() + 1e-9) * 0.9)
    print(f'{video}: mix peak {np.abs(mix).max():.2f}  rms {rms_db(mix):.1f} dB | vo {rms_db(vo):.1f}  music {rms_db(music * duck):.1f}  sfx {rms_db(sfx):.1f}')


if __name__ == '__main__':
    main()
