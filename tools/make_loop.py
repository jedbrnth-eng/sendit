#!/usr/bin/env python3
# Copyright (c) 2026 Jed Brown
# SPDX-License-Identifier: GPL-3.0-only
# Part of SendIt: https://github.com/jedbrnth-eng/sendit

"""Make seamless audio loops: equal-power crossfade of the tail into the head, then report the
seam step vs the clip's typical sample step (a click shows as a seam step far above typical).
usage: tools/make_loop.py <in> <out.wav> [start_s] [len_s] [xfade_s]
       tools/make_loop.py --check <file.wav|ogg> [...]
"""
import subprocess, sys, numpy as np, wave

def read(path):
    raw = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "s16le", "-ac", "1", "-ar", "44100", "-"],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, dtype=np.int16).astype(np.float64) / 32768.0

def seam_report(x):
    step = np.abs(np.diff(x))
    seam = abs(x[0] - x[-1])
    return seam, float(np.percentile(step, 99.9))

def make(src, dst, start, length, xf):
    x = read(src)
    sr = 44100
    a, n, f = int(start * sr), int(length * sr), int(xf * sr)
    n = min(n, len(x) - a - f)  # never read past the source
    seg = x[a:a + n + f].copy()
    t = np.linspace(0, 1, f)
    head = seg[:f] * np.sin(t * np.pi / 2) + seg[n:n + f] * np.cos(t * np.pi / 2)
    out = np.concatenate([head, seg[f:n]])
    out *= 0.89 / max(1e-6, np.max(np.abs(out)))  # -1 dBFS peak
    with wave.open(dst, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(sr)
        w.writeframes((out * 32767).astype(np.int16).tobytes())
    return out

if __name__ == "__main__":
    if sys.argv[1] == "--check":
        bad = 0
        for p in sys.argv[2:]:
            seam, p999 = seam_report(read(p))
            ok = seam <= p999
            bad += not ok
            print(f"{'ok  ' if ok else 'FAIL'} {p}: seam step {seam:.4f} vs p99.9 step {p999:.4f}")
        sys.exit(1 if bad else 0)
    src, dst = sys.argv[1], sys.argv[2]
    start = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
    length = float(sys.argv[4]) if len(sys.argv) > 4 else 8.0
    xf = float(sys.argv[5]) if len(sys.argv) > 5 else 0.5
    out = make(src, dst, start, length, xf)
    seam, p999 = seam_report(out)
    print(f"{dst}: {len(out)/44100:.2f}s seam {seam:.4f} vs p99.9 {p999:.4f}")
