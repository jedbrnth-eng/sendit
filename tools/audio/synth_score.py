# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""SendIt score + UI one-shots, rendered from code (numpy + scipy + tools/audio/dsp.py only).

One instrument family for the whole set, all in D major so overlapping sounds never clash:
  * EP voice   - soft FM electric-piano / mallet pluck (1:1 FM with a decaying index, a short
                 in-key bell partial, a felt-soft 3 ms raised-cosine attack, warm low-pass).
  * air        - a quiet band-passed pink-noise swish (the single 'shimmer/air' element).
  * pad        - filtered band-limited saw (warm 'synth brass') only for the bigger stingers.
  * thump      - a soft sine 'lock-in' under bank stingers / deny.

Deterministic (fixed seeds). Output: 16-bit PCM mono 44.1 kHz, peak -3 dBFS, faded head/tail.
Run:  cd <repo> && python3 tools/audio/synth_score.py   (needs numpy + scipy)
"""
import os, sys
import numpy as np
from scipy import signal

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsp  # noqa: E402
from dsp import SR, n_of, t_of, midi_hz, rng, lp, hp, bp, fade, trim_tail, normalize, place  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_SCORE = os.path.join(ROOT, "assets", "sfx", "score")
OUT_UI = os.path.join(ROOT, "assets", "sfx", "ui")
PEAK_DB = -3.0

# D major pentatonic ladder (MIDI): D5 E5 F#5 A5 B5 D6 E6 F#6 A6 B6
LADDER = [74, 76, 78, 81, 83, 86, 88, 90, 93, 95]
N = {"D3": 50, "A3": 57, "D4": 62, "F#4": 66, "G4": 67, "A4": 69, "B4": 71, "C#5": 73, "D5": 74, "E5": 76,
     "F#5": 78, "G5": 79, "A5": 81, "B5": 83, "C#6": 85, "D6": 86, "E6": 88, "F#6": 90, "G6": 91, "A6": 93,
     "B6": 95, "D7": 98}


# ----------------------------------------------------------------------------- voices
def soft_attack(n, attack):
    """Raised-cosine attack ramp (no leading-edge click)."""
    e = np.ones(n)
    na = max(2, n_of(attack))
    na = min(na, n)
    e[:na] = 0.5 - 0.5 * np.cos(np.linspace(0, np.pi, na))
    return e


def ep(midi, dur, vel=1.0, sparkle=0.0, detune_c=0.0, tone=1.0, decay=None, attack=0.003, r=None, cutoff=None,
       body=0.0):
    """The set's one instrument: a soft felt-mallet bar (marimba/kalimba family).

    Modal bar partials 1 : 4 : ~9.9 (+ a little 2nd), every upper mode shorter than the fundamental,
    a band-passed 'wood' strike (soft raised-cosine attack, never a click), warm low-pass.
    (Round 1 used a 1:1 FM e-piano; earshot read it as 'cheap synthesized beep' z ~3.0 and
    'coin pickup' up to 4.9, the bar reads beep ~2.3 / marimba ~3.0, see the PR notes.)
    vel      loudness + strike hardness     sparkle  level of the 4th-partial 'bell' (in key)
    tone     scales the upper modes          decay    fundamental tau (s); default shortens with pitch
    body     extra low 'wood' knock + 2nd-partial warmth (gap ladder: read less 'beep', see below)
    """
    f = midi_hz(midi) * 2 ** (detune_c / 1200)
    n = n_of(dur)
    t = t_of(n)
    tau = decay if decay is not None else float(np.clip(0.12 * (587.33 / f) ** 0.3, 0.07, 0.2))
    r = r if r is not None else rng(int(midi))
    hard = 0.7 + 0.3 * vel
    modes = [(1.0, 1.0, tau), (2.0, 0.07 * tone, tau * 0.5), (4.0, (0.18 + 0.2 * sparkle) * tone * hard, tau * 0.25),
             (9.9, 0.07 * tone * hard, tau * 0.08)]
    x = np.zeros(n)
    for k, a, d in modes:
        fk = f * k
        if fk > 5200:  # keep the set below ~5 kHz: fold the bell partial down an octave instead
            if k == 4.0 and f * 2 < 5200:
                fk, a = f * 2.0, a * 0.6
            else:
                continue
        x += a * np.sin(2 * np.pi * fk * t + r.uniform(0, 2 * np.pi)) * np.exp(-t / d)
    x *= soft_attack(n, attack)
    nz = r.standard_normal(n) * np.exp(-t / 0.004) * soft_attack(n, 0.0012)
    x += 0.25 * hard * bp(nz, 400, 3000)
    if body:
        nz2 = r.standard_normal(n) * np.exp(-t / 0.006) * soft_attack(n, 0.0012)
        x += body * hard * bp(nz2, 300, 2000)
        x += 0.67 * body * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t / (tau * 0.4)) * soft_attack(n, attack)
    fc = cutoff if cutoff is not None else 5000.0
    x = lp(x, fc, 2)
    return vel * x


def air(dur, lo=1800, hi=6500, rise=0.04, fall=0.12, r=None, level=1.0, sweep=None):
    """Quiet airy swish: pink noise, band-passed. sweep=(f_start, f_end) morphs between two plain
    low-passes (no resonance: round 1's resonant SVF sweep whistled and read 'power-up' / 'beep')."""
    n = n_of(dur)
    t = t_of(n)
    z = dsp.noise(n, r, "pink")
    if sweep is None:
        z = bp(z, lo, hi, 2)
    else:
        w = np.clip(t / (rise + fall), 0, 1) ** 0.7
        z = hp(lp(z, sweep[0], 2) * (1 - w) + lp(z, sweep[1], 2) * w, 300, 2)
    e = np.where(t < rise, (t / rise) ** 2, np.exp(-(t - rise) / fall))
    z = z * e
    return level * z / (np.max(np.abs(z)) + 1e-12)


def pad(midis, dur, attack=0.15, release=0.3, cutoff=(700, 2200), r=None, detune=6.0):
    """Warm 'synth brass' pad: two detuned band-limited saws per note, filter opening with the swell."""
    n = n_of(dur)
    t = t_of(n)
    sig = np.zeros(n)
    for m in midis:
        f = midi_hz(m)
        for d in (-detune, detune):
            ff = np.full(n, f * 2 ** (d / 1200))
            sig += dsp.osc(ff, "saw", 0.0 if r is None else r.uniform(0, 6.28))
    env = np.clip(t / attack, 0, 1) ** 1.5
    env *= np.where(t > dur - release, np.clip((dur - t) / release, 0, 1), 1.0)
    dark = lp(sig, cutoff[0], 2)
    bright = lp(sig, cutoff[1], 2)
    open_ = np.clip(t / (attack * 1.5), 0, 1) * np.exp(-np.maximum(t - attack, 0) / 0.5)
    y = (dark * (1 - open_) + bright * open_) * env
    return y / (np.max(np.abs(y)) + 1e-12)


def thump(dur=0.18, f_hi=120.0, f_lo=62.0, tau=0.06):
    n = n_of(dur)
    t = t_of(n)
    fr = f_lo + (f_hi - f_lo) * np.exp(-t / 0.025)
    y = np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.exp(-t / tau) * soft_attack(n, 0.004)
    return y


def shimmer(midis, dur, r, rate=7.0, attack=0.12, tau=0.45):
    """Soft high sine cluster with slow attack and gentle tremolo (the 'sparkle' tail)."""
    n = n_of(dur)
    t = t_of(n)
    y = np.zeros(n)
    for k, m in enumerate(midis):
        ph = r.uniform(0, 6.28)
        y += np.sin(2 * np.pi * midi_hz(m) * t + ph) * (1 + 0.35 * np.sin(2 * np.pi * (rate + k) * t + ph))
    e = (1 - np.exp(-t / attack)) * np.exp(-t / tau)
    return y * e / max(1, len(midis))


# ----------------------------------------------------------------------------- finishing
def room(x, r, rt60=0.3, wet=0.1, pre=0.006):
    """Small computed room like dsp.room, length-safe (dsp.room can be off by one sample)."""
    n = n_of(rt60 * 1.2)
    ir = r.standard_normal(n) * np.exp(-6.91 * t_of(n) / rt60)
    ir = lp(ir, 5000)
    ir[: n_of(pre)] = 0
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
    y = np.concatenate([x, np.zeros(n)])
    w = signal.fftconvolve(x, ir)
    y[: len(w)] += wet * w[: len(y)]
    return y


def finish(x, max_dur, fin=0.0015, fout=0.04, wet=0.0, r=None, rt60=0.25, floor_db=-60.0):
    if wet > 0:
        x = room(x, r, rt60=rt60, wet=wet, pre=0.006)
    x = hp(x, 25, 2)
    n = min(len(x), n_of(max_dur))
    x = x[:n].copy()
    x = trim_tail(x, floor_db=floor_db, keep=0.015)
    x = fade(x, fin, min(fout, len(x) / SR * 0.3))
    x = x - np.mean(x) * np.hanning(len(x)) / np.mean(np.hanning(len(x)))  # DC -> 0 without a step
    x = fade(x, fin, 0.004)
    return normalize(x, PEAK_DB)


WRITTEN = []


def out(sub, name, x):
    path = os.path.join(OUT_SCORE if sub == "score" else OUT_UI, name)
    dsp.write(path, x)
    WRITTEN.append(path)


def seq(events, dur):
    """events: list of (t_sec, signal, gain)."""
    buf = np.zeros(n_of(dur) + 1)
    for ts, s, g in events:
        place(buf, s, ts, g)
    return buf


# ----------------------------------------------------------------------------- score set
def gaps():
    # Round 3: shorter bar decay (0.7x) + low wood knock + 2nd-partial warmth. Mean over 6 renders:
    # earshot 'cheap synthesized beep' z 2.22 -> 1.97, 'coin pickup' 2.54 -> 2.00, marimba ~3.3.
    variants = {  # vel, tone, detune (cents), sparkle offset, seed
        "a": (0.95, 1.00, 0.0, 0.00, 11),
        "b": (0.85, 0.90, +2.0, -0.05, 12),
        "c": (1.05, 1.08, -2.0, +0.05, 13),
    }
    for step, m in enumerate(LADDER):
        tau = 0.7 * float(np.clip(0.12 * (587.33 / midi_hz(m)) ** 0.3, 0.07, 0.2))
        for v, (vel, tone, det, sp, seed) in variants.items():
            r = rng(1000 + step * 10 + seed)
            sparkle = 0.25 + 0.06 * step + sp  # higher steps: a touch more bell
            x = ep(m, 0.5, vel=vel, sparkle=sparkle, detune_c=det, tone=tone, decay=tau, body=0.3, r=r)
            out("score", f"gap_{step:02d}_{v}.wav", finish(x, 0.36, fout=0.08, wet=0.06, r=r, rt60=0.2))


def chord(t, notes, vel, r, decay=0.3, g=0.8, tone=0.8, body=0.0, det=0.0):
    """Block chord on the mallet bar (all notes struck together: a chord, not a coin-style rise)."""
    return [(t, ep(N[nm], 0.9, vel=vel, tone=tone, decay=decay, r=r, body=body, detune_c=det * (-1) ** k), g)
            for k, nm in enumerate(notes)]


def latch(r, dur=0.06):
    """Short mechanical latch click (band-passed noise tick + a damped 900 Hz knock)."""
    n = n_of(dur)
    tt = t_of(n)
    z = r.standard_normal(n) * np.exp(-tt / 0.004) * soft_attack(n, 0.0008)
    return bp(z, 1500, 6000) + 0.3 * np.sin(2 * np.pi * 900 * tt) * np.exp(-tt / 0.008)


def split():
    # Round 4: one low block chord (D4 A4 D5 F#5 A5) + a body thump, struck together. Round 1-3's
    # grace-note rise (A5 -> D6) read 'coin pickup' z 4.4-4.9; this reads 3.4 (earshot, see PR).
    for v, (vel, det, seed) in {"a": (1.0, 0.0, 23), "b": (0.93, 2.0, 24), "c": (1.06, -2.0, 25)}.items():
        r = rng(seed)
        ev = chord(0.0, ("D4", "A4", "D5", "F#5", "A5"), vel, r, decay=0.2, tone=0.7, body=0.5, det=det)
        ev.append((0.0, thump(0.2, 150, 70, 0.05), 0.6))
        out("score", f"split_{v}.wav", finish(seq(ev, 0.7), 0.5, fout=0.12, wet=0.06, r=r))


def bank():
    # low-register strum resolving on D (round 1's high fast D5-D6 arpeggio read 'coin pickup' z 4.9)
    sizes = {
        "s": (["A3", "D4", "F#4", "A4", "D5"], 0.035, 0.55, 0.0),
        "m": (["D3", "A3", "D4", "F#4", "A4", "D5", "F#5", "D6"], 0.038, 0.85, 0.25),
        "l": (["D3", "A3", "D4", "F#4", "A4", "D5", "F#5", "A5", "D6"], 0.045, 1.35, 0.5),
    }
    for size, (notes, step, dur, padlvl) in sizes.items():
        for v, (vel, seed, det) in {"a": (1.0, 31, 0.0), "b": (0.93, 32, 1.5)}.items():
            r = rng(seed + ord(size))
            ev = [(0.0, thump(0.2, 130, 66, 0.055), 0.55 + 0.15 * padlvl)]
            for k, nm in enumerate(notes):
                last = k == len(notes) - 1
                d = 0.6 if not last else dur
                ev.append((k * step, ep(N[nm], d, vel=vel * (0.75 + 0.25 * k / len(notes)),
                                        sparkle=0.4 + 0.3 * last, detune_c=det * (-1) ** k,
                                        decay=0.35 if last else None, r=r), 0.9 if not last else 1.0))
            t_end = (len(notes) - 1) * step
            if size != "s":  # resolving D-major chord bloom under the last note
                for nm in ("D5", "F#5", "A5"):
                    ev.append((t_end, ep(N[nm], dur, vel=0.45, decay=0.3 + 0.2 * padlvl, r=r), 0.55))
                ev.append((t_end, shimmer([N["D7"], N["A6"]], dur, r, attack=0.08, tau=0.25 + 0.3 * padlvl), 0.06))
            if padlvl > 0:
                ev.append((0.02, pad([N["D3"], N["A3"], N["D4"], N["F#4"]], dur - 0.05, attack=0.1,
                                     release=dur * 0.6, cutoff=(600, 2000), r=r), 0.1 + 0.24 * padlvl))
            ev.append((0.0, air(0.4, 2500, 7000, rise=0.02, fall=0.08 + 0.1 * padlvl, r=r), 0.05))
            out("score", f"bank_{size}_{v}.wav",
                finish(seq(ev, dur + 0.4), dur, fout=dur * 0.35, wet=0.08 + 0.05 * padlvl, r=r, rt60=0.3 + 0.3 * padlvl))


def wipe():
    for v, (seed, first, second) in {"a": (41, "A4", "F#4"), "b": (42, "B4", "F#4")}.items():
        r = rng(seed)
        ev = [
            (0.0, ep(N[first], 0.4, vel=0.8, tone=0.7, decay=0.16, r=r, cutoff=1400), 1.0),
            (0.16, ep(N[second], 0.45, vel=0.75, tone=0.65, decay=0.2, detune_c=-6, r=r, cutoff=1100), 1.0),
            (0.16, ep(N["D4"], 0.45, vel=0.5, tone=0.6, decay=0.2, r=r, cutoff=900), 0.5),
        ]
        x = lp(seq(ev, 0.7), 1600, 2)
        out("score", f"wipe_{v}.wav", finish(x, 0.52, fout=0.15, wet=0.06, r=r))


def count_go():
    for v, (vel, tone, seed) in {"a": (1.0, 0.8, 51), "b": (0.92, 0.75, 52), "c": (1.05, 0.85, 53)}.items():
        r = rng(seed)
        x = ep(N["A4"], 0.3, vel=vel, tone=tone, sparkle=0.5, decay=0.06, attack=0.002, r=r, cutoff=2600)
        # woodblock-ish hollow resonance (in tune: 2nd harmonic), very short
        n = len(x)
        tt = t_of(n)
        x += 0.25 * np.sin(2 * np.pi * midi_hz(N["A5"]) * tt) * np.exp(-tt / 0.02) * soft_attack(n, 0.002)
        out("score", f"count_{v}.wav", finish(x, 0.2, fout=0.06, wet=0.04, r=r))
    r = rng(54)
    ev = [(0.0, air(0.4, sweep=(900, 4500), rise=0.05, fall=0.08, r=r), 0.08)]
    for nm, g in (("D5", 0.8), ("F#5", 0.75), ("A5", 0.75), ("D6", 0.9)):
        ev.append((0.03, ep(N[nm], 0.65, vel=1.05, sparkle=0.6, decay=0.22, r=r), g))
    ev.append((0.03, thump(0.2, 140, 74, 0.05), 0.45))
    out("score", "go.wav", finish(seq(ev, 0.8), 0.6, fout=0.2, wet=0.08, r=r))


def new_best():
    r = rng(61)
    st = 0.075
    seqs = [("D5", "F#5", "A5"), ("G5", "B5", "D6"), ("A5", "C#6", "E6")]
    ev = []
    tcur = 0.0
    for chord in seqs:
        for k, nm in enumerate(chord):
            ev.append((tcur + k * st * 0.5, ep(N[nm], 0.5, vel=0.8, sparkle=0.35, r=r), 0.75))
        tcur += 0.18
    tf = tcur + 0.04
    for nm, g in (("D5", 0.6), ("F#5", 0.6), ("A5", 0.65), ("D6", 0.9), ("F#6", 0.6)):
        ev.append((tf, ep(N[nm], 1.0, vel=1.0, sparkle=0.6, decay=0.4, r=r), g))
    ev.append((tf, pad([N["D4"], N["A4"], N["D5"], N["F#5"], N["A5"]], 1.5 - tf, attack=0.1, release=0.7,
                       cutoff=(700, 2400), r=r), 0.35))
    ev.append((tf, thump(0.25, 120, 62, 0.07), 0.5))
    ev.append((tf, shimmer([N["D7"], N["A6"], N["F#6"]], 1.5 - tf, r, attack=0.1, tau=0.5), 0.08))
    ev.append((tf - 0.12, air(0.5, sweep=(900, 5000), rise=0.11, fall=0.15, r=r), 0.07))
    out("score", "new_best.wav", finish(seq(ev, 1.9), 1.5, fout=0.45, wet=0.12, r=r, rt60=0.5))


def results():
    r = rng(71)
    ev = [(0.0, pad([N["D3"], N["A3"], N["D4"], N["F#4"]], 0.8, attack=0.12, release=0.5, cutoff=(500, 1400), r=r), 0.35)]
    for k, nm in enumerate(("D4", "A4", "D5", "F#5", "A5")):
        ev.append((0.02 + 0.03 * k, ep(N[nm], 0.7, vel=0.6, tone=0.7, decay=0.3, attack=0.004, r=r), 0.5))
    ev.append((0.1, shimmer([N["A6"], N["D7"]], 0.7, r, attack=0.2, tau=0.35), 0.05))
    out("score", "results.wav", finish(seq(ev, 1.0), 0.8, fout=0.3, wet=0.1, r=r, rt60=0.4))


def level_up():
    # Round 4: a swelling D-major pad that lands on one mallet chord + thump (no fast rising
    # arpeggio: round 1-3's 7-note D4->D6 run read 'coin pickup' z 4.1; this reads 3.0).
    r = rng(81)
    ev = [(0.0, pad([N["D3"], N["A3"], N["D4"], N["F#4"], N["A4"]], 1.2, attack=0.32, release=0.6, cutoff=(500, 1800),
                    r=r), 0.4)]
    ev += chord(0.3, ("D4", "F#4", "A4", "D5"), 0.9, r, decay=0.45, body=0.25)
    ev.append((0.3, thump(0.25, 120, 60, 0.07), 0.5))
    ev.append((0.0, air(0.45, sweep=(400, 3000), rise=0.3, fall=0.1, r=r), 0.08))
    out("score", "level_up.wav", finish(seq(ev, 1.6), 1.3, fout=0.45, wet=0.12, r=r, rt60=0.5))


def bell(midi, dur, r, vel=1.0, tau=0.5):
    """Soft harmonic bell (all partials in key: 1, 2, 3, 4 with slight beating pair)."""
    f = midi_hz(midi)
    n = n_of(dur)
    parts = [(1.0, 1.0, tau), (1.0015, 0.5, tau * 0.9), (2.0, 0.35, tau * 0.45), (3.0, 0.12, tau * 0.25),
             (4.0, 0.05, tau * 0.15)]
    fr = [f * m for m, a, d in parts if f * m < 5500]
    am = [a for m, a, d in parts if f * m < 5500]
    dc = [d * 6.91 for m, a, d in parts if f * m < 5500]  # modal() takes T60
    x = dsp.modal(fr, dc, am, n, r=r)
    return vel * x * soft_attack(n, 0.004)


def unlock():
    # Round 4: latch click + thump + low open chord (D4 A4 D5). Round 1-3's D6 -> A6 bell rise read
    # 'coin pickup' z 4.0; this reads 2.7 and scores best on the positive queries (3.5).
    r = rng(93)
    ev = [(0.0, latch(r), 0.6), (0.04, thump(0.18, 140, 70, 0.04), 0.5)]
    ev += chord(0.04, ("D4", "A4", "D5"), 0.85, r, decay=0.35, tone=0.6, body=0.4)
    out("score", "unlock.wav", finish(seq(ev, 1.0), 0.8, fout=0.3, wet=0.09, r=r, rt60=0.4))


def replay_in():
    r = rng(101)
    ev = [(0.0, air(0.75, sweep=(300, 4200), rise=0.45, fall=0.12, r=r), 0.55)]
    tc = 0.42
    for nm, g in (("D4", 0.5), ("A4", 0.5), ("D5", 0.6), ("F#5", 0.55), ("A5", 0.5)):
        ev.append((tc, ep(N[nm], 0.5, vel=0.55, tone=0.7, decay=0.22, attack=0.006, r=r), g))
    ev.append((tc, pad([N["D4"], N["A4"], N["F#5"]], 0.48, attack=0.04, release=0.35, cutoff=(500, 1500), r=r), 0.25))
    x = seq(ev, 1.1)
    out("score", "replay_in.wav", finish(x, 0.9, fout=0.3, wet=0.08, r=r, rt60=0.35))


# ----------------------------------------------------------------------------- UI set
def ui():
    # move: tiny wooden tick with a pentatonic pitch per variant (round robin stays musical); the
    # strike noise dominates (round 1's mostly-tonal tick read 'cheap synthesized beep' z 3.4)
    for v, (nm, seed) in {"a": ("D6", 1), "b": ("E6", 2), "c": ("F#6", 3), "d": ("A6", 4)}.items():
        r = rng(200 + seed)
        x = 0.35 * ep(N[nm], 0.09, vel=0.7, tone=0.6, decay=0.018, attack=0.0015, r=r, cutoff=3500)
        n = len(x)
        tt = t_of(n)
        x += 0.6 * bp(r.standard_normal(n), 600, 3000) * np.exp(-tt / 0.003) * soft_attack(n, 0.001)
        out("ui", f"move_{v}.wav", finish(x, 0.065, fout=0.02))
    for v, (vel, seed) in {"a": (1.0, 11), "b": (0.92, 12)}.items():
        r = rng(210 + seed)
        ev = [(0.0, ep(N["D5"], 0.25, vel=0.6 * vel, tone=0.6, decay=0.06, r=r, cutoff=2500), 1.0),
              (0.085, ep(N["A5"], 0.3, vel=0.85 * vel, tone=0.6, decay=0.09, r=r, cutoff=3000), 1.0),
              (0.085, ep(N["D5"], 0.3, vel=0.5 * vel, tone=0.5, decay=0.09, r=r), 0.5)]
        out("ui", f"confirm_{v}.wav", finish(seq(ev, 0.4), 0.25, fout=0.08, wet=0.05, r=r))
        r = rng(220 + seed)
        ev = [(0.0, ep(N["A5"], 0.25, vel=0.8 * vel, sparkle=0.2, tone=0.8, decay=0.07, r=r), 1.0),
              (0.07, ep(N["D5"], 0.3, vel=0.85 * vel, tone=0.75, decay=0.1, r=r, cutoff=2200), 1.0)]
        out("ui", f"back_{v}.wav", finish(seq(ev, 0.4), 0.25, fout=0.08, wet=0.05, r=r))
    r = rng(231)
    hit = lambda: (thump(0.12, 170, 95, 0.03) * 0.8 + 0.5 * ep(N["D3"], 0.12, vel=0.8, tone=0.5, decay=0.035, r=r, cutoff=700))
    x = lp(seq([(0.0, hit(), 1.0), (0.095, hit(), 0.8)], 0.3), 1200, 2)
    out("ui", "deny.wav", finish(x, 0.25, fout=0.06))
    for v, (nm, seed) in {"a": ("A6", 1), "b": ("B6", 2), "c": ("D7", 3)}.items():
        r = rng(240 + seed)
        x = 0.25 * ep(N[nm], 0.05, vel=0.6, tone=0.5, decay=0.009, attack=0.0012, r=r, cutoff=4000)
        n = len(x)
        tt = t_of(n)
        x += 0.6 * bp(r.standard_normal(n), 800, 3500) * np.exp(-tt / 0.0025) * soft_attack(n, 0.0008)
        out("ui", f"tick_{v}.wav", finish(x, 0.035, fout=0.012))
    r = rng(251)
    ev = [(0.0, air(0.3, sweep=(800, 4000), rise=0.1, fall=0.06, r=r), 0.15),
          (0.09, ep(N["A5"], 0.25, vel=0.7, tone=0.7, decay=0.08, r=r), 1.0),
          (0.09, ep(N["D5"], 0.25, vel=0.6, decay=0.08, r=r), 0.6)]
    out("ui", "open.wav", finish(seq(ev, 0.45), 0.3, fout=0.1, wet=0.05, r=r))
    r = rng(252)
    ev = [(0.0, air(0.3, sweep=(4000, 700), rise=0.04, fall=0.09, r=r), 0.2),
          (0.05, ep(N["D5"], 0.25, vel=0.65, tone=0.75, decay=0.08, r=r, cutoff=2400), 1.0),
          (0.05, ep(N["A4"], 0.25, vel=0.45, tone=0.7, decay=0.08, r=r, cutoff=2000), 0.6)]
    out("ui", "close.wav", finish(seq(ev, 0.45), 0.3, fout=0.1, wet=0.05, r=r))


def main():
    gaps(); split(); bank(); wipe(); count_go(); new_best(); results(); level_up(); unlock(); replay_in(); ui()
    total = sum(os.path.getsize(p) for p in WRITTEN)
    print(f"wrote {len(WRITTEN)} files, {total} bytes")


if __name__ == "__main__":
    main()
