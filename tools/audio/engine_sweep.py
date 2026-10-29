#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Offline engine sweep: crossfade an engine profile's RPM loops (equal power) with pitch
scaling, like scripts/audio/car_audio.gd does at runtime, over a scripted RPM/load path.
Writes a WAV so the engine can be measured / listened to without running the game.

usage: tools/audio/engine_sweep.py <profile|old> <out.wav> [seconds=10]
'old' sweeps the pre-overhaul loops (assets/sfx/loop_*.wav from git history must be on disk at
$OLD_DIR) for a BEFORE/AFTER comparison.
"""
import os, sys, wave
import numpy as np
sys.path.insert(0, os.path.dirname(__file__))
import dsp  # noqa: E402
from synth_engine import RPMS  # noqa: E402


def load(path):
    with wave.open(path) as w:
        x = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").astype(np.float64) / 32768
        return x, w.getframerate()


def path_rpm(t, dur):
    """Idle 1 s, pull through three gears (rise, drop on shift), lift at the end."""
    seg = (dur - 2.0) / 3
    if t < 1.0:
        return 1000, 0.0
    if t > dur - 1.0:
        return 7500 - (t - (dur - 1.0)) * 3500, 0.0
    k = (t - 1.0) % seg / seg
    return 3200 + k * 4300, 1.0


def main():
    prof, out = sys.argv[1], sys.argv[2]
    dur = float(sys.argv[3]) if len(sys.argv) > 3 else 10.0
    if prof == "old":
        d = os.environ.get("OLD_DIR", "assets/sfx")
        names = ["loop_0.wav", "loop_1_0.wav", "loop_2_0.wav", "loop_3_0.wav", "loop_4_0.wav", "loop_5_0.wav"]
        pts = [950.0, 2200.0, 3600.0, 5000.0, 6400.0, 7800.0]
        on = [load(f"{d}/{n}") for n in names]
        off = on
    else:
        pts = [float(r) for r in RPMS]
        on = [load(f"{os.environ.get('ENGINE_DIR', 'assets/sfx/engine')}/{prof}_{r}_on.wav") for r in RPMS]
        off = [load(f"{os.environ.get('ENGINE_DIR', 'assets/sfx/engine')}/{prof}_{r}_off.wav") for r in RPMS]
    sr = dsp.SR
    n = int(dur * sr)
    y = np.zeros(n)
    pos_on = np.zeros(len(pts))
    pos_off = np.zeros(len(pts))
    block = 256
    load_s = 0.0
    for b in range(0, n, block):
        t = b / sr
        rpm, ld = path_rpm(t, dur)
        load_s += (ld - load_s) * min(1.0, block / sr * 8)
        hi = 1
        while hi < len(pts) - 1 and rpm > pts[hi]:
            hi += 1
        lo = hi - 1
        x = np.clip((rpm - pts[lo]) / (pts[hi] - pts[lo]), 0, 1)
        w = {lo: np.cos(x * np.pi / 2), hi: np.sin(x * np.pi / 2)}
        m = min(block, n - b)
        for i, wi in w.items():
            rate = rpm / pts[i]
            for bank, pos, gl in ((on, pos_on, np.sin(load_s * np.pi / 2)), (off, pos_off, np.cos(load_s * np.pi / 2))):
                src, ssr = bank[i]
                idx = (pos[i] + np.arange(m) * rate * ssr / sr) % len(src)
                i0 = idx.astype(int)
                fr = idx - i0
                s = src[i0] * (1 - fr) + src[(i0 + 1) % len(src)] * fr
                y[b:b + m] += wi * gl * s
        for i in range(len(pts)):
            rate = rpm / pts[i]
            pos_on[i] = (pos_on[i] + m * rate * on[i][1] / sr) % len(on[i][0])
            pos_off[i] = (pos_off[i] + m * rate * off[i][1] / sr) % len(off[i][0])
    dsp.write(out, dsp.normalize(y, -1.0))
    print(out)


if __name__ == "__main__":
    main()
