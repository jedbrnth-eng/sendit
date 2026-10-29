# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Shared DSP for SendIt's procedural sound assets (numpy + scipy only, deterministic).

Every generator in tools/audio/synth_*.py builds on this. All output is our own synthesis
(CC0, see CREDITS.md); no recorded audio goes in. Sample rate matches Godot's default mix rate
so nothing is resampled at runtime.
"""
import os, wave
import numpy as np
from scipy import signal

SR = 44100


def rng(seed):
    return np.random.default_rng(seed)


def n_of(sec):
    return int(round(sec * SR))


def t_of(n):
    return np.arange(n) / SR


def noise(n, r, color="white"):
    x = r.standard_normal(n)
    if color == "pink":
        # Voss-McCartney-ish via 1/f filter (Paul Kellet's economy coefficients)
        b, a = [0.049922035, -0.095993537, 0.050612699, -0.004408786], [1, -2.494956002, 2.017265875, -0.522189400]
        x = signal.lfilter(b, a, x)
    elif color == "brown":
        x = np.cumsum(x)
        x = signal.lfilter([1, -1], [1, -0.995], x)
    return x / (np.max(np.abs(x)) + 1e-12)


def bp(x, lo, hi, order=2):
    sos = signal.butter(order, [lo, min(hi, SR / 2 * 0.98)], "bandpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lp(x, f, order=2):
    sos = signal.butter(order, min(f, SR / 2 * 0.98), "lowpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def hp(x, f, order=2):
    sos = signal.butter(order, f, "highpass", fs=SR, output="sos")
    return signal.sosfilt(sos, x)


def lp_circular(x, f, order=2):
    """Zero-phase-ish circular low-pass for loops: filter three copies, keep the middle."""
    y = lp(np.concatenate([x, x, x]), f, order)
    return y[len(x):2 * len(x)]


def filt_circular(x, fn):
    y = fn(np.concatenate([x, x, x]))
    return y[len(x):2 * len(x)]


def peq(x, f0, gain_db, q=1.0):
    """RBJ peaking EQ."""
    a_ = 10 ** (gain_db / 40)
    w0 = 2 * np.pi * f0 / SR
    al = np.sin(w0) / (2 * q)
    b = [1 + al * a_, -2 * np.cos(w0), 1 - al * a_]
    a = [1 + al / a_, -2 * np.cos(w0), 1 - al / a_]
    return signal.lfilter(b, a, x)


def reson(x, f0, q):
    """Two-pole resonator (constant peak gain)."""
    w0 = 2 * np.pi * f0 / SR
    bw = w0 / q
    rr = np.exp(-bw / 2)
    a = [1, -2 * rr * np.cos(w0), rr * rr]
    b = [1 - rr]
    return signal.lfilter(b, a, x)


def env_exp(n, tau, attack=0.001):
    t = t_of(n)
    e = np.exp(-t / max(tau, 1e-5))
    na = max(1, n_of(attack))
    e[:na] *= np.linspace(0, 1, na)
    return e


def modal(freqs, decays, amps, n, r=None, jitter=0.0):
    """Sum of decaying sines (struck object). decays = T60-ish seconds."""
    t = t_of(n)
    out = np.zeros(n)
    for f, d, a in zip(freqs, decays, amps):
        if r is not None and jitter:
            f *= 1 + r.uniform(-jitter, jitter)
        ph = 0 if r is None else r.uniform(0, 2 * np.pi)
        out += a * np.sin(2 * np.pi * f * t + ph) * np.exp(-6.91 * t / d)
    return out


def osc(freq, shape="sine", phase0=0.0):
    """Phase-continuous oscillator from a per-sample frequency array."""
    ph = phase0 + 2 * np.pi * np.cumsum(freq) / SR
    if shape == "sine":
        return np.sin(ph)
    if shape == "saw":
        return band_saw(ph, freq)
    if shape == "square":
        return np.tanh(4 * np.sin(ph))
    if shape == "tri":
        return 2 / np.pi * np.arcsin(np.sin(ph))
    raise ValueError(shape)


def band_saw(ph, freq, nmax=60):
    """Additive band-limited saw (no aliasing) from a phase array."""
    out = np.zeros_like(ph)
    fmax = np.max(freq)
    k_lim = max(1, min(nmax, int(SR / 2 / max(fmax, 1))))
    for k in range(1, k_lim + 1):
        g = np.where(freq * k < SR / 2 * 0.95, 1.0, 0.0)
        out += g * np.sin(k * ph) / k
    return out * (2 / np.pi)


def soft_clip(x, drive=1.0):
    return np.tanh(x * drive) / np.tanh(drive)


def fade(x, fin=0.002, fout=0.02):
    x = x.copy()
    a, b = n_of(fin), n_of(fout)
    if a:
        x[:a] *= np.sin(np.linspace(0, np.pi / 2, a)) ** 2
    if b:
        x[-b:] *= np.cos(np.linspace(0, np.pi / 2, b)) ** 2
    return x


def trim_tail(x, floor_db=-66.0, keep=0.02):
    env = np.abs(x)
    thr = 10 ** (floor_db / 20) * np.max(env)
    idx = np.flatnonzero(env > thr)
    end = min(len(x), (idx[-1] if idx.size else 0) + n_of(keep))
    return fade(x[:end], 0.0, keep)


def normalize(x, peak_db=-1.0):
    return x * (10 ** (peak_db / 20) / (np.max(np.abs(x)) + 1e-12))


def norm_rms(x, rms_db):
    rms = np.sqrt(np.mean(x ** 2)) + 1e-12
    y = x * (10 ** (rms_db / 20) / rms)
    pk = np.max(np.abs(y))
    if pk > 0.89:  # never above -1 dBFS
        y *= 0.89 / pk
    return y


def place(dst, x, t_sec, gain=1.0):
    i = n_of(t_sec)
    j = min(len(dst), i + len(x))
    if j > i:
        dst[i:j] += gain * x[: j - i]
    return dst


def room(x, r, rt60=0.35, wet=0.12, pre=0.008):
    """Small computed room (noise-tail IR), mono."""
    n = n_of(rt60 * 1.2)
    ir = r.standard_normal(n) * np.exp(-6.91 * t_of(n) / rt60)
    ir = lp(ir, 6000)
    ir[: n_of(pre)] = 0
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-12
    wetx = signal.fftconvolve(x, ir)
    y = np.concatenate([x, np.zeros(n)])
    y[: min(len(y), len(wetx))] += wet * wetx[: len(y)]
    return y


def write(path, x, peak_db=None):
    """16-bit PCM WAV, mono or (n,2) stereo. Never above -1 dBFS unless peak_db says lower."""
    x = np.asarray(x, dtype=np.float64)
    if peak_db is not None:
        x = normalize(x, peak_db)
    pk = np.max(np.abs(x))
    if pk > 0.891:
        x = x * (0.891 / pk)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    ch = 1 if x.ndim == 1 else x.shape[1]
    with wave.open(path, "wb") as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype("<i2").tobytes())
    return x


def seam_ok(x):
    """Loop seam check like tools/make_loop.py: wrap step must not exceed the p99.9 sample step."""
    m = x if x.ndim == 1 else x.mean(axis=1)
    step = np.abs(np.diff(m))
    return abs(m[0] - m[-1]) <= np.percentile(step, 99.9)


def midi_hz(m):
    return 440.0 * 2 ** ((m - 69) / 12)
