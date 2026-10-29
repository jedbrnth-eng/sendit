#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""SendIt road / crash / pass-by sound set, synthesized (CC0, our own code; no recorded audio inside).

Physics-first: every sound is "what strikes what, and what rings":
  * contacts are excitation signals (impulses, micro-impact clouds, contact noise) with irregular timing;
  * the struck things are resonator banks (car panels, joint plates, glass shards, cone shells, chassis,
    suspension/body) whose decay times are set from material damping (sheet steel crumpled = short,
    glass shards = bright + short, plastic shell = low + damped);
  * the listener is a mic in a space: short computed reflections (length-safe room below), a gentle
    cabin/air low-pass where the sound is heard from inside or far away, and a -66 dB noise floor.

Loops are built circularly: noise generated for the loop length, every IIR filter run via
dsp.filt_circular, periodic events placed modulo the loop length, periods chosen as integer counts.

usage: python3 tools/audio/synth_road_crash.py   (writes under assets/sfx/{road,crash,pass,traffic})
"""
import os, sys
import numpy as np
from scipy import signal

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsp  # noqa: E402
from dsp import SR, n_of, t_of  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(ROOT, "assets", "sfx")
PEAK = -3.0


# ---------------------------------------------------------------- shared building blocks

def q_for(f, t60):
    """dsp.reson Q that gives the wanted T60 (s) at f: bw = 13.8 / (T60 * SR) rad/sample."""
    return max(0.5, (2 * np.pi * f / SR) / (13.8 / (t60 * SR)))


def bank(x, freqs, t60s, gains):
    out = np.zeros_like(x)
    for f, d, g in zip(freqs, t60s, gains):
        if f < SR / 2 * 0.95:
            out += g * dsp.reson(x, f, q_for(f, d))
    return out


def room(x, r, rt60=0.25, wet=0.12, pre=0.006, refl=((0.0041, 0.35), (0.0093, 0.22))):
    """Length-safe small space: discrete early reflections (hard surfaces) + a lp'd noise-tail IR."""
    n = n_of(rt60 * 1.2)
    ir = r.standard_normal(n) * np.exp(-6.91 * t_of(n) / rt60)
    ir = dsp.lp(ir, 5000)
    ir[: n_of(pre)] = 0
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
    y = np.zeros(len(x) + n)
    y[: len(x)] += x
    w = signal.fftconvolve(x, ir)[: len(y)]
    y[: len(w)] += wet * w
    for dt, g in refl:
        k = n_of(dt)
        y[k:k + len(x)] += g * dsp.lp(x, 3500)[: len(y) - k]
    return y


def mic_floor(n, r, db=-66.0):
    """Pink-ish mic/preamp floor at db re full scale peak (added after normalising to the target)."""
    f = dsp.noise(n, r, "pink")
    f = f / (np.sqrt(np.mean(f ** 2)) + 1e-12)
    return f * 10 ** (db / 20)


def finish(x, r, peak_db=PEAK, floor_db=-66.0, fin=0.0015, tail_db=-60.0, fout=0.04):
    x = x - np.mean(x)
    x = dsp.hp(x, 22)
    x = dsp.normalize(x, peak_db)
    # trim the silent tail (measured on the dry signal, before the mic floor goes in)
    env = np.abs(x)
    thr = 10 ** (tail_db / 20)
    idx = np.flatnonzero(env > thr)
    end = min(len(x), (idx[-1] if idx.size else len(x)) + n_of(fout))
    x = x[:end] + mic_floor(end, r, floor_db)
    x = dsp.fade(x, fin, fout)
    x[0] = 0.0
    return dsp.normalize(x, peak_db)


def save(rel, x):
    p = os.path.join(OUT, rel)
    dsp.write(p, x)
    return p


def burst(n, r, tau, lo=None, hi=None, attack=0.0005):
    z = r.standard_normal(n) * dsp.env_exp(n, tau, attack)
    if lo and hi:
        z = dsp.bp(z, lo, hi)
    elif hi:
        z = dsp.lp(z, hi)
    elif lo:
        z = dsp.hp(z, lo)
    return z


def drop_sine(n, f0, f1, tau_f, tau_a, r, attack=0.002):
    """Pitch-dropping body thump: f(t) = f1 + (f0 - f1) e^{-t/tau_f}."""
    t = t_of(n)
    f = f1 + (f0 - f1) * np.exp(-t / tau_f)
    return dsp.osc(f, "sine", r.uniform(0, 0.3)) * dsp.env_exp(n, tau_a, attack)


def impulses(n, times, amps, width_s=0.0003, r=None):
    """Excitation train: each contact a short raised-cosine pulse (width ~ contact stiffness)."""
    x = np.zeros(n)
    for t, a in zip(times, amps):
        w = max(2, n_of(width_s * (1 if r is None else r.uniform(0.6, 1.6))))
        i = n_of(t)
        if i + w < n:
            x[i:i + w] += a * np.hanning(w)
    return x


# circular tools for loops
def circ(x, fn):
    return dsp.filt_circular(x, fn)


def place_circ(buf, x, i):
    idx = (i + np.arange(len(x))) % len(buf)
    np.add.at(buf, idx, x)


def cbank(x, freqs, t60s, gains):
    return circ(x, lambda z: bank(z, freqs, t60s, gains))


def cpink(n, r):
    w = r.standard_normal(n)
    b, a = [0.049922035, -0.095993537, 0.050612699, -0.004408786], [1, -2.494956002, 2.017265875, -0.522189400]
    return circ(w, lambda z: signal.lfilter(b, a, z))


def smooth_rand(n, r, fc):
    """Circular smooth random curve, unit-ish rms, bandwidth fc."""
    z = circ(r.standard_normal(n), lambda y: dsp.lp(y, fc, 2))
    return z / (np.sqrt(np.mean(z ** 2)) + 1e-12)


def croom(x, r, rt60=0.15, wet=0.1):
    """Circular reflections for loops: the IR wraps around the loop."""
    n = n_of(rt60 * 1.2)
    ir = r.standard_normal(n) * np.exp(-6.91 * t_of(n) / rt60)
    ir = dsp.lp(ir, 5000)
    ir[: n_of(0.005)] = 0
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
    X = np.fft.rfft(x)
    H = np.fft.rfft(ir, len(x))
    return x + wet * np.fft.irfft(X * H, len(x))


def loop_finish(x, r):
    x = x - np.mean(x)
    x = dsp.normalize(x, PEAK)
    x = x + circ(mic_floor(len(x), r), lambda z: z)
    return dsp.normalize(x, PEAK)


# ---------------------------------------------------------------- loops

def rumble_strip():
    r = dsp.rng(101)
    per, k = 490, 90
    n = per * k
    exc = np.zeros(n)
    slap = np.zeros(n)
    for i in range(k):
        for side, off in ((0, 0), (1, r.integers(18, 40))):
            a = r.uniform(0.75, 1.15) * (1.0 if side == 0 else 0.8)
            w = int(r.integers(70, 120))
            place_circ(exc, np.hanning(2 * w) * a, i * per + off + int(r.integers(-6, 7)))
            # tyre-tread slap: soft 1.5 ms onset (an instant noise onset read as a click, 36/s)
            sb = r.standard_normal(300) * dsp.env_exp(300, r.uniform(30, 70) / SR, 0.0015) * a
            place_circ(slap, sb, i * per + off + w)
    body = cbank(exc, [42, 58, 78, 96, 118, 180, 270], [0.25, 0.2, 0.15, 0.12, 0.1, 0.06, 0.05],
                 [1.0, 1.2, 1.1, 0.9, 0.7, 0.35, 0.2])
    body = circ(body, lambda z: dsp.lp(z, 900, 2))
    slap = circ(slap, lambda z: dsp.bp(z, 300, 2500))
    rattle = cbank(slap, [640, 910, 1370, 2050, 2900], [0.03, 0.025, 0.02, 0.02, 0.015], [0.4, 0.3, 0.25, 0.15, .1])
    roll = circ(cpink(n, r), lambda z: dsp.peq(dsp.bp(z, 80, 4000), 700, 6, 0.8))
    y = 1.0 * body / np.std(body) + 0.3 * slap / np.std(slap) + 0.2 * rattle / np.std(rattle) \
        + 0.8 * roll / np.std(roll)
    y = croom(y, r, 0.08, 0.08)
    y = circ(y, lambda z: dsp.soft_clip(z / np.max(np.abs(z)) * 1.2, 1.0))
    y = circ(y, lambda z: dsp.lp(z, 3500, 2))  # heard through the car body: no hard top end
    return loop_finish(y, r)


def shoulder_grit():
    r = dsp.rng(202)
    n = n_of(2.0)
    roll_env = 0.6 + 0.4 * np.tanh(smooth_rand(n, r, 8))
    crush = cgrains(n, r, 1400, 250, 3500, 0.0015, 0.004, 0.6) * roll_env  # >=1.5 ms grains: crunch, not ticks
    low = circ(cpink(n, r), lambda z: dsp.lp(z, 700)) * roll_env
    stones = np.zeros(n)
    t = 0.0
    while True:  # stones flicked into the wheel arch: short ticks, not ringing pings
        t += r.exponential(1 / 14)
        if t >= 2.0:
            break
        m = n_of(0.03)
        ex = np.zeros(m)
        ex[:n_of(0.001)] = np.hanning(n_of(0.001))  # 1 ms strike, not a one-sample impulse
        f = r.uniform(1500, 3500)
        tick = dsp.reson(ex, f, q_for(f, r.uniform(0.004, 0.01))) \
            + 0.5 * burst(m, r, 0.0015, lo=1500, hi=4000, attack=0.001)
        tick += 0.6 * dsp.reson(ex, r.uniform(350, 800), q_for(600, 0.012))  # arch liner
        place_circ(stones, tick * r.uniform(0.2, 1.0) ** 2, n_of(t))
    y = crush / np.std(crush) + 0.7 * low / np.std(low) + 0.2 * stones / (np.std(stones) + 1e-9)
    y = croom(y, r, 0.07, 0.1)
    y = circ(y, lambda z: dsp.lp(z, 4000, 2))
    return loop_finish(y, r)


def scrape():
    r = dsp.rng(303)
    n = n_of(1.5)
    # contact excitation: stick-slip of panel edge on rough concrete = dense random impulses + noise
    am = smooth_rand(n, r, 45)
    am = 0.5 + 0.5 * np.tanh(1.3 * am)
    am2 = 0.6 + 0.4 * np.tanh(smooth_rand(n, r, 6))
    exc = r.standard_normal(n) * am * am2
    ss = np.zeros(n)  # stick-slip catches as 1 ms hann pulses (single-sample impulses clicked, 37/s)
    hw = np.hanning(n_of(0.001))
    for i in np.flatnonzero(r.random(n) < 900 / SR):
        place_circ(ss, hw * r.uniform(-1, 1) * 2, i)
    exc = exc + ss
    fr = np.sort(r.uniform(300, 3000, 34))
    metal = cbank(exc, fr, r.uniform(0.04, 0.12, 34), r.uniform(0.3, 1.0, 34))
    grind = circ(exc, lambda z: dsp.bp(z, 1500, 9000)) * 0.6
    low = circ(r.standard_normal(n) * am2, lambda z: dsp.lp(z, 220, 2))
    # spark crackle: tiny broadband clicks in clusters
    spk = np.zeros(n)
    t = 0.0
    while True:
        t += r.exponential(1 / 7)
        if t >= 1.5:
            break
        for _ in range(int(r.integers(3, 12))):
            c = burst(n_of(0.006), r, 0.0012, lo=2500, hi=7000, attack=0.0008)
            place_circ(spk, c * r.uniform(0.3, 1.0), n_of(t + r.uniform(0, 0.03)))
    y = metal / np.std(metal) + 0.55 * grind / np.std(grind) + 0.5 * low / np.std(low) \
        + 0.5 * spk / (np.std(spk) + 1e-9) * 0.4
    y = croom(y, r, 0.1, 0.08)
    y = circ(y, lambda z: dsp.soft_clip(z / np.max(np.abs(z)) * 1.6, 1.4))
    y = circ(y, lambda z: dsp.lp(z, 6000, 2))
    return loop_finish(y, r)


def tyre_roll(tb_g=0.6, var=0.3):
    """Pink roll noise + jittered tread-block slap (~650/s), wheel-rotation and slow road-surface
    variation, low texture rumble, sparse stone pops; hump ~650 Hz, roll-off above 3 kHz."""
    r = dsp.rng(404)
    n = n_of(2.0); t = t_of(n)
    p = cpink(n, r)
    rot = 1 + 0.08 * np.sin(2 * np.pi * 14 * t) + 0.04 * np.sin(2 * np.pi * 28 * t + 1.1)
    rot *= 1 + var * smooth_rand(n, r, 2)
    tb = np.zeros(n); tt = 0.0
    while True:
        tt += 1 / 650 * r.uniform(0.6, 1.4)
        if tt >= 2.0:
            break
        m = int(r.integers(6, 14)); place_circ(tb, np.hanning(m) * r.uniform(0.3, 1.0), n_of(tt))
    tb = circ(tb - tb.mean(), lambda z: dsp.bp(z, 300, 2500))
    tex = circ(r.standard_normal(n) * (0.5 + 0.5 * np.abs(smooth_rand(n, r, 12))), lambda z: dsp.bp(z, 40, 180))
    pops = cgrains(n, r, 40, 800, 5000, 0.0003, 0.001, 0.9)
    y = (p / np.std(p) + tb_g * tb / np.std(tb)) * rot + 0.8 * tex / np.std(tex) + 0.3 * pops / np.std(pops)
    y = circ(y, lambda z: dsp.peq(z, 650, 6, 0.9))
    y = circ(y, lambda z: dsp.lp(z, 3000, 4))
    y = circ(y, lambda z: dsp.hp(z, 35, 2))
    y = croom(y, r, 0.06, 0.06)
    return loop_finish(y, r)


def hum(gas_g=0.15, tyre_g=3.0, lpf=2200, harm=0.4, rough=0.2):
    """4-cyl at ~2490 rpm heard at 5-20 m: 83.05 Hz firing with per-cylinder imbalance (half orders),
    exhaust gas noise per firing, muffler low-pass, tyre roll, air absorption, roadside reflections.
    Tyre-led defaults: the engine-led mix (gas .45, tyre .7, harm 1, lpf 3k) read 'motorboat' / no
    match (earshot z +1.1); tyre-led reads z +2.0, 'car driving past' 13% forced choice."""
    r = dsp.rng(505)
    per, k = 531, 168
    n = per * k
    exc = np.zeros(n); gas = np.zeros(n)
    cyl = r.uniform(0.8, 1.15, 4)
    for i in range(k):
        a = cyl[i % 4] * (1 + rough * r.standard_normal())
        w = int(r.integers(40, 70)); i0 = i * per + int(r.integers(-4, 5))
        place_circ(exc, np.hanning(w) * a, i0)
        place_circ(gas, r.standard_normal(260) * np.exp(-np.arange(260) / 70) * a, i0 + 10)
    hf = [83.05 * j for j in (0.5, 1, 1.5, 2, 3, 4, 5, 6)]
    ex = cbank(exc, hf, [0.1, 0.08, 0.06, 0.06, 0.05, 0.04, 0.03, 0.02], [0.3 * harm, 1.0, 0.25 * harm, 0.7, .5 * harm, .3 * harm, .2 * harm, .1 * harm])
    ex = circ(ex + 0.4 * circ(exc, lambda z: dsp.lp(z, 300)), lambda z: dsp.lp(z, 900, 2))
    gas = circ(gas, lambda z: dsp.bp(z, 150, 1800))
    tyres = circ(cpink(n, r), lambda z: dsp.lp(dsp.peq(z, 600, 5, 0.9), 2200, 2))
    y = ex / np.std(ex) + gas_g * gas / np.std(gas) + tyre_g * tyres / np.std(tyres)
    y = circ(y, lambda z: dsp.lp(z, lpf, 2))
    y = croom(y, r, 0.2, 0.15)
    return loop_finish(y, r)


# ---------------------------------------------------------------- road one-shots


def thud(seed):
    r = dsp.rng(seed)
    n = n_of(0.62)
    force = burst(n, r, r.uniform(0.012, 0.02), hi=400, attack=0.002)
    ch = bank(force, r.uniform([50, 72, 100, 140, 210, 300], [60, 85, 115, 160, 240, 340]),
              [0.35, 0.3, 0.22, 0.15, 0.1, 0.07], [1.0, .9, .7, .5, .35, .25])
    sweep = drop_sine(n, r.uniform(100, 115), 44, 0.05, 0.11, r, 0.003)
    panel = bank(burst(n, r, 0.006, 150, 2000), np.sort(r.uniform(180, 480, 6)), [0.06] * 6, r.uniform(.4, 1, 6))
    grit = grains(n, r, 0.002, 0.045, 30, 500, 4000, 0.0003, 0.002, 1.5)
    rat = np.zeros(n)
    for _ in range(int(r.integers(3, 6))):
        b = bank(impulses(n_of(0.05), [0.0], [1], 0.0002, r), [r.uniform(600, 2200)], [0.025], [1])
        dsp.place(rat, b * r.uniform(0.3, 1.0), r.uniform(0.07, 0.25))
    y = ch / np.max(np.abs(ch)) + 0.45 * sweep + 0.3 * panel / np.max(np.abs(panel)) \
        + 0.12 * grit / np.max(np.abs(grit)) + 0.06 * rat / (np.max(np.abs(rat)) + 1e-9)
    y = dsp.soft_clip(y / np.max(np.abs(y)) * 2.0, 1.6)
    y = room(y, r, 0.28, 0.1)
    return finish(y, r)


def crunch(seed, heavy, body=0.6, tear=1.0, drive=5.0, glassmix=0.2, low_lo=40):
    """Crumple: folds of micro-impacts through short-decay panel modes, tearing grit, bumper cracks,
    chassis boom and a few headlight-glass bits; hard saturation like a close mic on a real crash."""
    r = dsp.rng(seed)
    n = n_of(0.95)
    dur = r.uniform(0.15, 0.2) if not heavy else r.uniform(0.2, 0.26)
    nf = int(r.integers(5, 9) if not heavy else r.integers(9, 15))
    ft = np.sort(0.003 + dur * r.beta(1.2, 2.5, nf)); ft[0] = 0.003
    exc = np.zeros(n)
    for k, t in enumerate(ft):
        A = 1.3 if k == 0 else r.uniform(0.5, 1.0) * np.exp(-(t - 0.003) / (dur * 0.8))
        span = r.uniform(0.01, 0.035); cnt = int(r.integers(8, 22))
        tt = t + span * r.random(cnt) ** 1.5
        exc += A * impulses(n, tt, r.uniform(0.2, 1.0, cnt) ** 2, 0.00007, r)
        exc += A * 0.25 * grains(n, r, t, t + span, cnt * 2, 300, 12000, 0.0002, 0.0025)
    nm = 72 if heavy else 56
    fr = np.exp(r.uniform(np.log(250), np.log(6500), nm))
    dec = r.uniform(0.015, 0.06, nm) * (500 / fr) ** 0.3
    metal = bank(exc, fr, dec, r.uniform(0.3, 1.0, nm))
    metal = dsp.soft_clip(metal / np.max(np.abs(metal)) * 2.5, 2.0)
    env = dsp.lp(np.abs(exc), 40); env = env / (np.max(env) + 1e-12)
    tr = dsp.bp(r.standard_normal(n), 900, 7000) * env
    pl = np.zeros(n)
    for _ in range(int(r.integers(3, 6) if heavy else r.integers(2, 4))):
        c = burst(n_of(0.02), r, r.uniform(0.0015, 0.004), 600, 8000)
        dsp.place(pl, c * r.uniform(0.5, 1.0), r.uniform(0.0, dur))
    force = burst(n, r, 0.02, hi=250)
    boom = bank(force, r.uniform([low_lo, 70, 100, 150], [low_lo + 15, 90, 125, 190]), [0.3, 0.22, 0.16, 0.1], [1, .8, .6, .4])
    y = metal / np.max(np.abs(metal)) + tear * tr / (np.max(np.abs(tr)) + 1e-9) \
        + 0.5 * pl / (np.max(np.abs(pl)) + 1e-9) + body * boom / np.max(np.abs(boom))
    if glassmix:
        g = tinkle(r, n, 0.01, 60, 0.5, 2500, 11000, 1.0)
        y += glassmix * g / np.max(np.abs(g))
    y = dsp.soft_clip(y / np.max(np.abs(y)) * drive, drive * 0.8)
    y = room(y, r, 0.35, 0.12)
    return finish(y, r)


def tinkle(r, n, t_start, count, span, f_lo=2000, f_hi=8000, gain=1.0, bounce=True):
    """Small glass/plastic bits landing on asphalt: each bit bounces with shrinking intervals."""
    y = np.zeros(n)
    for _ in range(count):
        t = t_start + span * r.random() ** 1.6
        f = np.exp(r.uniform(np.log(f_lo), np.log(f_hi)))
        a = r.uniform(0.2, 1.0) ** 2 * gain
        gap = r.uniform(0.03, 0.12)
        for b in range(int(r.integers(1, 5)) if bounce else 1):
            m = n_of(0.04)
            p = dsp.modal([f, f * r.uniform(1.5, 1.8), f * r.uniform(2.6, 3.1)],
                          [r.uniform(0.008, 0.03)] * 3, [1, 0.6, 0.3], m, r)
            p[:5] *= np.linspace(0, 1, 5)
            dsp.place(y, p * a, t)
            t += gap
            gap *= r.uniform(0.45, 0.7)
            a *= r.uniform(0.35, 0.6)
    return y


def debris(seed):
    r = dsp.rng(seed)
    n = n_of(1.3)
    y = tinkle(r, n, 0.004, int(r.integers(40, 70)), r.uniform(0.7, 0.95))
    # chunks of plastic skittering (low-mid ticks)
    y += tinkle(r, n, 0.01, int(r.integers(8, 14)), 0.7, 500, 1500, 0.5)
    scat = burst(n, r, 0.35, 1500, 7000) * 0.04 * (0.4 + np.abs(dsp.lp(r.standard_normal(n), 30)) * 3)
    y = y + scat
    y = room(y, r, 0.3, 0.15, refl=((0.006, 0.3), (0.015, 0.2)))
    return finish(y, r)


def glass(seed):
    r = dsp.rng(seed)
    n = n_of(1.2)
    cnt = int(r.integers(200, 320))
    tt = 0.003 + 0.035 * r.random(cnt) ** 2
    aa = r.uniform(0.3, 1.0, cnt) ** 2
    exc = impulses(n, tt, aa, 0.00005, r)
    fr = np.exp(r.uniform(np.log(2500), np.log(15000), 80))
    crack = bank(exc, fr, r.uniform(0.008, 0.04, 80), r.uniform(0.3, 1.0, 80))
    crack += 0.8 * dsp.hp(exc, 4000)
    crack += grains(n, r, 0.002, 0.05, 200, 3000, 16000, 0.0001, 0.001, 2.0) * 0.5
    shards = tinkle(r, n, 0.03, int(r.integers(130, 190)), r.uniform(0.25, 0.4), 3500, 14000, 1.0)
    falling = tinkle(r, n, 0.15, int(r.integers(60, 90)), 0.8, 3000, 12000, 0.5)
    y = crack / np.max(np.abs(crack)) + 0.6 * shards / np.max(np.abs(shards)) \
        + 0.35 * falling / (np.max(np.abs(falling)) + 1e-9)
    y = dsp.hp(y, 500)
    y = room(y, r, 0.35, 0.14)
    return finish(y, r)



def barrier(seed, water):
    r = dsp.rng(seed)
    n = n_of(0.8)
    t = t_of(n)
    force = burst(n, r, 0.02, hi=350, attack=0.002)
    th = bank(force, [45, 66, 90, 125], [0.3, 0.25, 0.18, 0.12], [1, .8, .6, .4]) + 0.3 * drop_sine(n, 80, 40, 0.05, 0.1, r)
    cr = grains(n, r, 0.002, 0.08, int(r.integers(60, 90)), 700, 9000, 0.0003, 0.004, 1.8)
    chips = tinkle(r, n, 0.05, int(r.integers(10, 18)), 0.45, 1000, 4000, 0.6)
    ex = impulses(n, 0.004 + 0.1 * r.random(60) ** 2, r.uniform(0.1, 0.8, 60) ** 2, 0.0001, r)
    fr = np.exp(r.uniform(np.log(250), np.log(5000), 40))
    mt = bank(ex, fr, r.uniform(0.02, 0.05, 40), r.uniform(0.3, 1, 40))
    mt = dsp.soft_clip(mt / np.max(np.abs(mt)) * 2, 1.6)
    se = np.clip((t - 0.08) / 0.03, 0, 1) * np.exp(-np.clip(t - 0.11, 0, None) / 0.14)
    sc = r.standard_normal(n) * se * (0.5 + 0.5 * np.tanh(dsp.lp(r.standard_normal(n), 40) * 16))
    sc = bank(sc, np.sort(r.uniform(400, 3000, 16)), [0.05] * 16, r.uniform(0.3, 1, 16)) + 0.5 * dsp.bp(sc, 1500, 8000)
    y = 0.8 * th / np.max(np.abs(th)) + 0.55 * cr / np.max(np.abs(cr)) + 0.7 * mt + 0.4 * sc / np.max(np.abs(sc)) \
        + 0.12 * chips / (np.max(np.abs(chips)) + 1e-9)
    if water:  # water-filled plastic barrier: hollow shell boom + slosh
        sh = bank(impulses(n, [0.003], [1], 0.002, r), [95, 160, 240, 380], [0.18, 0.12, 0.08, 0.05], [1, .7, .5, .3])
        sl = dsp.lp(r.standard_normal(n), 600) * np.clip((t - 0.05) / 0.05, 0, 1) * np.exp(-np.clip(t - 0.1, 0, None) / 0.2)
        sl *= 0.5 + 0.5 * np.sin(2 * np.pi * 6 * t) ** 2
        y = y + 0.6 * sh / np.max(np.abs(sh)) + 0.25 * sl / np.max(np.abs(sl))
    y = dsp.soft_clip(y / np.max(np.abs(y)) * 1.6, 1.3)
    y = room(y, r, 0.3, 0.12)
    return finish(y, r)


def ring():
    r = dsp.rng(707)
    n = n_of(2.4)
    t = t_of(n)
    f = 3600 * (1 + 0.002 * np.sin(2 * np.pi * 0.7 * t))
    y = dsp.osc(f, "sine") + 0.15 * dsp.osc(f * 1.0035, "sine", 1.0)
    env = np.ones(n)
    a = n_of(0.05)
    env[:a] = np.sin(np.linspace(0, np.pi / 2, a)) ** 2
    s = n_of(0.5)
    env[s:] = np.cos(np.linspace(0, np.pi / 2, n - s)) ** 2  # 1.9 s fade-out
    y = y * env
    y[0] = 0
    return dsp.normalize(y, -12.0)


def grains(n, r, t0, t1, count, lo=300, hi=6000, gmin=0.0002, gmax=0.002, skew=1.0):
    """Cloud of tiny noise grains (micro-fractures / crushing grit) between t0 and t1."""
    y = np.zeros(n)
    for _ in range(count):
        m = max(4, n_of(r.uniform(gmin, gmax)))
        g = r.standard_normal(m) * np.hanning(m) * r.lognormal(0, 0.7)
        t = t0 + (t1 - t0) * r.random() ** skew
        i = n_of(t)
        if i + m < n:
            y[i:i + m] += g
    return dsp.bp(y, lo, hi)


def cgrains(n, r, rate, lo, hi, gmin, gmax, sigma=0.8):
    y = np.zeros(n)
    t = 0.0
    while True:
        t += r.exponential(1 / rate)
        if t >= n / SR:
            break
        m = max(4, n_of(r.uniform(gmin, gmax)))
        place_circ(y, r.standard_normal(m) * np.hanning(m) * r.lognormal(0, sigma), n_of(t))
    return circ(y, lambda z: dsp.bp(z, lo, hi))


# ---------------------------------------------------------------- main

def main():
    paths = []
    paths.append(save("road/rumble_strip_loop.wav", rumble_strip()))
    paths.append(save("road/shoulder_grit_loop.wav", shoulder_grit()))
    paths.append(save("road/scrape_loop.wav", scrape()))
    paths.append(save("road/tyre_roll_loop.wav", tyre_roll()))
    for i in range(4):
        paths.append(save(f"crash/thud_{'abcd'[i]}.wav", thud(21 + i)))
    for i in range(6):
        paths.append(save(f"crash/crunch_{'abcdef'[i]}.wav", crunch(31 + i, i >= 2)))
    for i in range(4):
        paths.append(save(f"crash/debris_{'abcd'[i]}.wav", debris(41 + i)))
    for i in range(3):
        paths.append(save(f"crash/glass_{'abc'[i]}.wav", glass(51 + i)))
    paths.append(save("crash/barrier_a.wav", barrier(71, False)))
    paths.append(save("crash/barrier_b.wav", barrier(72, True)))
    paths.append(save("crash/ring.wav", ring()))
    paths.append(save("traffic/hum_loop.wav", hum()))
    for p in paths:
        print(os.path.relpath(p, ROOT))


if __name__ == "__main__":
    main()
