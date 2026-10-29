#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""SendIt police sound set, synthesized (CC0, our own code; no recorded audio inside).

A real electronic siren IS an oscillator: a timer/RC circuit sweeps a square-ish tone that a power
amplifier drives into a compression-driver horn loudspeaker. So every voice here is:

    phase-continuous oscillator (square + a little saw, small duty asymmetry)
      -> amplifier/driver nonlinearity (asymmetric soft clip)
      -> horn loudspeaker (band-pass ~450 Hz-4.5 kHz, resonant peaks ~1.1 / 2.3 / 3.4 kHz)
      -> cone/diaphragm breakup grit (signal-modulated band noise, ~-30 dB)
      -> short computed outdoor reflections (ground bounce + two facade echoes, no reverb tail)

Loops are rendered so that both the sweep and the oscillator phase return exactly to their start at
the loop end (the frequency curve is scaled by <0.1% so the total phase is an integer number of
cycles), every IIR filter runs circularly (dsp.filt_circular) and echoes are circular shifts.
Doppler and distance are added at runtime by the game, so everything is dry and close.

usage: python3 tools/audio/synth_police.py [out_dir]   (default assets/sfx/police)
"""
import os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dsp  # noqa: E402
from dsp import SR  # noqa: E402

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
PEAK_DB = -2.0


# ---------------------------------------------------------------- oscillator + horn voice

def phase_of(freq, phase0=0.0):
    return phase0 + 2 * np.pi * np.cumsum(freq) / SR


def close_phase(freq):
    """Scale a periodic frequency curve so the loop holds an integer number of oscillator cycles."""
    cycles = np.sum(freq) / SR
    return freq * (max(1, round(cycles)) / cycles)


def siren_osc(freq, phase0=0.0, saw_mix=0.3, duty=0.08, nh=40):
    """Band-limited square (with a small duty skew -> some even harmonics) plus a little saw."""
    ph = phase_of(freq, phase0)
    sq = np.zeros_like(ph)
    for k in range(1, nh + 1):
        g = (freq * k < SR / 2 * 0.92).astype(float)
        if not g.any():
            break
        # pulse wave of duty 0.5+duty: harmonic k amplitude sin(pi k d)/k
        d = 0.5 + duty
        sq += g * (np.sin(np.pi * k * d) / k) * np.cos(k * ph - np.pi * k * d)
    sq *= 4 / np.pi / 2
    saw = dsp.band_saw(ph, freq, nmax=nh)
    return (1 - saw_mix) * sq + saw_mix * saw


def driver(x, drive=2.2, bias=0.12):
    """Amplifier + compression driver: asymmetric soft clip (bias adds even harmonics)."""
    y = np.tanh(drive * (x + bias)) - np.tanh(drive * bias)
    return y / np.max(np.abs(y) + 1e-12)


def horn_eq(x):
    """Horn loudspeaker response: steep roll-off below ~450 Hz, resonant peaks, top roll-off."""
    y = dsp.hp(x, 430, order=4)
    y = dsp.lp(y, 4800, order=2)
    y = dsp.peq(y, 1150, 5.0, q=1.8)
    y = dsp.peq(y, 2350, 6.5, q=2.6)
    y = dsp.peq(y, 3400, 2.5, q=3.0)
    y = dsp.peq(y, 6500, -6.0, q=0.7)
    return y


def grit(x, r, level=0.035):
    """Diaphragm breakup: band noise riding the signal's instantaneous magnitude."""
    n = r.standard_normal(len(x))
    return level * n * np.abs(x)


def grit_eq(x):
    return dsp.bp(x, 1800, 6000, order=2)


def reflections(x, circular):
    """Ground bounce (~2.5 ms, dull) + two facade echoes (~38 ms, ~95 ms). No reverb tail."""
    taps = [(dsp.n_of(0.0026), 0.45), (dsp.n_of(0.038), 0.16), (dsp.n_of(0.095), 0.08)]
    if circular:
        wet = sum(g * np.roll(x, d) for d, g in taps)
        wet = dsp.filt_circular(wet, lambda v: dsp.lp(v, 3200))
        return x + wet
    pad = taps[-1][0] + 1
    y = np.concatenate([x, np.zeros(pad)])
    wet = np.zeros_like(y)
    for d, g in taps:
        wet[d:d + len(x)] += g * x
    return y + dsp.lp(wet, 3200)


def periodic_noise(n, r, cutoff_hz):
    """Smooth random curve that is exactly periodic over n samples (band-limited in the FFT domain)."""
    spec = np.fft.rfft(r.standard_normal(n))
    fr = np.fft.rfftfreq(n, 1 / SR)
    spec[fr > cutoff_hz] = 0
    spec[0] = 0
    y = np.fft.irfft(spec, n)
    return y / (np.max(np.abs(y)) + 1e-12)


def outdoor(y, r, circular):
    """Air turbulence flutter (+-0.6 dB, <6 Hz) and a quiet outdoor floor (~-50 dB), loop-safe."""
    n = len(y)
    if circular:
        flut = periodic_noise(n, r, 6.0)
        floor = periodic_noise(n, r, 2500.0) * 0.6 + periodic_noise(n, r, 300.0) * 0.4
    else:
        flut = dsp.lp(r.standard_normal(n), 6.0, order=2)
        flut /= np.max(np.abs(flut)) + 1e-12
        floor = dsp.lp(r.standard_normal(n), 1500.0)
        floor /= np.max(np.abs(floor)) + 1e-12
    y = y * 10 ** (0.6 * flut / 20)
    if not circular:  # one-shots stay silent around the event
        return y
    return y + floor * np.max(np.abs(y)) * 10 ** (-50 / 20)


def horn_voice(freq, r, circular, amp=None, drive=2.2, saw_mix=0.3):
    if circular:  # component drift: +-0.25 % pitch wander, periodic so the loop still closes
        freq = close_phase(freq * (1 + 0.0025 * periodic_noise(len(freq), r, 1.5)))
    x = siren_osc(freq, saw_mix=saw_mix)
    if amp is not None:
        x = x * amp
    x = driver(x, drive=drive)
    if amp is not None:
        x = x * np.clip(amp * 1.5, 0, 1)  # keep the clip from lifting the fade-in/out back up
    g = grit(x, r)
    if circular:
        y = dsp.filt_circular(x, horn_eq) + dsp.filt_circular(g, grit_eq)
    else:
        y = horn_eq(x) + grit_eq(g)
    return outdoor(reflections(y, circular), r, circular)


# ---------------------------------------------------------------- sweep laws (log-frequency, RC timer)

def rc_sweep(n, lo, hi, rise_frac, tau_up, tau_dn):
    """One cycle of an RC-timer sweep in log frequency: charge (rise) then discharge (fall)."""
    nu = int(round(n * rise_frac))
    nd = n - nu
    tu = np.arange(nu) / nu
    td = np.arange(nd) / nd
    up = (1 - np.exp(-tu / tau_up)) / (1 - np.exp(-1 / tau_up))
    dn = 1 - (1 - np.exp(-td / tau_dn)) / (1 - np.exp(-1 / tau_dn))
    s = np.concatenate([up, dn])
    return np.exp(np.log(lo) + (np.log(hi) - np.log(lo)) * s)


def smooth_periodic(f, ms):
    """Circular moving average (driver/amp lag on hard frequency switches)."""
    k = max(1, dsp.n_of(ms / 1000))
    fk = np.fft.rfft(np.ones(k) / k, len(f))
    return np.fft.irfft(np.fft.rfft(f) * fk, len(f))


def loop_wail(r):
    cyc = dsp.n_of(4.3)
    f = rc_sweep(cyc, 640, 1480, 0.56, 0.45, 0.55)
    f = close_phase(np.tile(f, 2))
    return horn_voice(f, r, True), f


def loop_yelp(r):
    cyc = 13230  # 3.333 cycles/s, 8 cycles = 2.4 s
    f = rc_sweep(cyc, 660, 1480, 0.5, 0.5, 0.5)
    f = close_phase(np.tile(f, 8))
    return horn_voice(f, r, True), f


def loop_phaser(r):
    cyc = 4000  # 11.025 cycles/s, 16 cycles = 1.45 s
    f = rc_sweep(cyc, 720, 1520, 0.5, 0.6, 0.6)
    f = close_phase(np.tile(f, 16))
    return horn_voice(f, r, True), f



def oneshot_env(n, attack, release, total_keep=None):
    a = np.ones(n)
    na, nr = dsp.n_of(attack), dsp.n_of(release)
    a[:na] = np.sin(np.linspace(0, np.pi / 2, na)) ** 2
    a[-nr:] *= np.cos(np.linspace(0, np.pi / 2, nr)) ** 2
    return a


def finish(y):
    return dsp.fade(dsp.trim_tail(y, -60, 0.03), 0.0015, 0.03)


def whoop(r, lo, hi, t_rise, t_fall, end_hz):
    nu, nd = dsp.n_of(t_rise), dsp.n_of(t_fall)
    tu = np.arange(nu) / nu
    up = np.exp(np.log(lo) + (np.log(hi) - np.log(lo)) * (1 - np.exp(-tu / 0.55)) / (1 - np.exp(-1 / 0.55)))
    td = np.arange(nd) / nd
    dn = np.exp(np.log(hi) + (np.log(end_hz) - np.log(hi)) * td ** 0.8)
    f = np.concatenate([up, dn])
    n = len(f)
    amp = np.ones(n)
    na = dsp.n_of(0.012)
    amp[:na] = np.linspace(0, 1, na) ** 2
    amp[nu:] = np.cos(np.linspace(0, np.pi / 2, nd)) ** 1.5  # amp released with the fall
    return finish(horn_voice(f, r, False, amp=amp, drive=2.6))


def chirp(r):
    out = []
    for i, (lo, hi) in enumerate([(700, 1450), (720, 1500)]):
        nu, nd = dsp.n_of(0.07), dsp.n_of(0.08)
        f = np.concatenate([np.geomspace(lo, hi, nu), np.geomspace(hi, lo * 1.05, nd)])
        amp = np.ones(len(f))
        na = dsp.n_of(0.006)
        amp[:na] = np.linspace(0, 1, na)
        amp[-dsp.n_of(0.04):] *= np.linspace(1, 0, dsp.n_of(0.04)) ** 1.5
        out.append(f)
        out.append(amp)
    n_total = dsp.n_of(0.36)
    y_f = np.full(n_total, 700.0)
    y_a = np.zeros(n_total)
    for k, start in enumerate([0.0, 0.2]):
        f, a = out[2 * k], out[2 * k + 1]
        i = dsp.n_of(start)
        y_f[i:i + len(f)] = f
        y_a[i:i + len(a)] = a
    return finish(horn_voice(y_f, r, False, amp=y_a, drive=2.4))


def diaphragm_pulse(freq, phase0, duty, nh=80):
    """Air-horn diaphragm: it opens briefly once per cycle -> a narrow pulse train (flat, buzzy spectrum)."""
    ph = phase_of(freq, phase0)
    y = np.zeros_like(ph)
    for k in range(1, nh + 1):
        g = (freq * k < SR / 2 * 0.92).astype(float)
        if not g.any():
            break
        y += g * np.sinc(k * duty) * np.cos(k * ph)
    return y, ph


def air_horn(r, notes, dur, scoop_st=-1.8):
    """Truck/fire-engine air horn: 2-3 diaphragm horns (narrow-pulse buzz with cycle jitter), pitch
    scoop as the pressure builds, air turbulence gated by the diaphragm, trumpet bell formants."""
    n = dsp.n_of(dur)
    t = dsp.t_of(n)
    scoop = 2 ** (scoop_st * np.exp(-t / 0.04) / 12)
    sag = 2 ** (-0.6 * np.clip((t - (dur - 0.22)) / 0.22, 0, 1) ** 2 / 12)  # pressure drops on release
    amp = np.ones(n)
    na = dsp.n_of(0.045)  # valve opening: the column builds over ~45 ms
    amp[:na] = (1 - np.exp(-np.linspace(0, 4, na))) / (1 - np.exp(-4))
    nr = dsp.n_of(0.22)
    amp[-nr:] *= np.exp(-np.linspace(0, 5, nr))
    x = np.zeros(n)
    air = np.zeros(n)
    for i, fn in enumerate(notes):
        jit = dsp.lp(r.standard_normal(n), 120) * 0.012  # cycle-to-cycle jitter (rough buzz)
        wob = 0.002 * np.sin(2 * np.pi * (4.1 + 1.3 * i) * t + r.uniform(0, 6.28))
        f = fn * scoop * sag * (1 + jit + wob)
        pul, ph = diaphragm_pulse(f, r.uniform(0, 6.28), duty=0.16 + 0.03 * i)
        x += pul / np.max(np.abs(pul))
        gate = np.clip(np.cos(ph), 0, 1) ** 6  # turbulence bursts while the diaphragm is open
        air += gate * r.standard_normal(n)
    x = x / np.max(np.abs(x)) + 0.25 * dsp.bp(air, 1200, 7000) / (np.max(np.abs(air)) + 1e-12)
    x = driver(x * amp, drive=2.0, bias=0.1) * np.clip(amp * 1.4, 0, 1)
    # trumpet bells: cut-off ~250 Hz, broad formants, top roll-off
    y = dsp.hp(x, 250, order=3)
    y = dsp.peq(y, 650, 3.0, q=1.2)
    y = dsp.peq(y, 1350, 4.0, q=1.6)
    y = dsp.peq(y, 2600, 3.0, q=2.0)
    y = dsp.lp(y, 6000, order=2)
    return finish(outdoor(reflections(y, False), r, False))


# ---------------------------------------------------------------- main

LOOPS = {
    "siren_wail_loop.wav": (loop_wail, 101),
    "siren_yelp_loop.wav": (loop_yelp, 102),
    "siren_phaser_loop.wav": (loop_phaser, 104),
}


def render_all(out_dir):
    written = {}
    for name, (fn, seed) in LOOPS.items():
        y, f = fn(dsp.rng(seed))
        y = y - np.mean(y)
        y = dsp.write(os.path.join(out_dir, name), y, PEAK_DB)
        written[name] = (y, f)
    shots = {
        "whoop_a.wav": lambda r: whoop(r, 400, 1600, 0.35, 0.30, 820),
        "whoop_b.wav": lambda r: whoop(r, 430, 1700, 0.32, 0.34, 760),
        "horn_a.wav": lambda r: air_horn(r, [311.1, 370.0, 440.0], 1.25),
        "horn_b.wav": lambda r: air_horn(r, [329.6, 392.0, 466.2], 1.1, scoop_st=-2.3),
        "chirp.wav": chirp,
    }
    for i, (name, fn) in enumerate(shots.items()):
        y = fn(dsp.rng(200 + i))
        written[name] = (dsp.write(os.path.join(out_dir, name), y, PEAK_DB), None)
    return written


if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "assets", "sfx", "police")
    for name, (y, f) in render_all(out).items():
        extra = ""
        if f is not None:
            extra = f" f {f.min():.0f}-{f.max():.0f} Hz seam_ok={dsp.seam_ok(y)}"
        print(f"{name}: {len(y) / SR:.3f}s peak {20 * np.log10(np.max(np.abs(y))):.2f} dBFS{extra}")
